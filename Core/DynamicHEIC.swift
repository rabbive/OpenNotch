import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How far a render has got. A still is one frame.
public struct RenderProgress: Equatable, Sendable {
    public var framesDone: Int
    public var frameCount: Int

    public init(framesDone: Int = 0, frameCount: Int = 1) {
        self.framesDone = framesDone
        self.frameCount = frameCount
    }
}

/// A time-of-day or light-and-dark wallpaper: one HEIC with several frames, and apple_desktop XMP
/// tags (solar, h24, apr) that tell macOS when to show each frame.
public enum DynamicHEIC {
    static let appleDesktop = "http://ns.apple.com/namespace/1.0/"

    /// Renders every frame the way `WallpaperRenderer.render` renders a still, then writes the frames
    /// in their original order with their apple_desktop tags, so macOS keeps switching on schedule.
    /// `progress` is called from the rendering threads as each frame finishes.
    public static func render(
        _ source: URL,
        to destination: URL,
        geometry: BarGeometry,
        placement: Placement,
        background: RGBA,
        corners: CornerStyle,
        progress: @Sendable (RenderProgress) -> Void = { _ in }
    ) throws {
        guard let images = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(images) > 0
        else { throw RenderError(description: "Can't read \(source.lastPathComponent)") }
        let count = CGImageSourceGetCount(images)
        let frames = FrameSlots(count: count)
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let frame = Result<CGImage, any Error> {
                // Each thread opens its own reader, so no ImageIO object is shared across threads.
                guard let reader = CGImageSourceCreateWithURL(source as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(reader, index, nil)
                else { throw RenderError(description: "Can't read frame \(index) of \(source.lastPathComponent)") }
                return try WallpaperRenderer.render(image, geometry: geometry, placement: placement, background: background, corners: corners)
            }
            progress(RenderProgress(framesDone: frames.store(at: index, frame), frameCount: count))
        }

        let partial = destination.appendingPathExtension("partial")
        guard let output = CGImageDestinationCreateWithURL(partial as CFURL, UTType.heic.identifier as CFString, count, nil)
        else { throw RenderError(description: "Can't write \(destination.lastPathComponent)") }
        for index in 0..<count {
            let frame = try frames[index]!.get()
            if let tags = try appleDesktopTags(of: images, at: index) {
                CGImageDestinationAddImageAndMetadata(output, frame, tags, nil)
            } else {
                CGImageDestinationAddImage(output, frame, nil)
            }
        }
        guard CGImageDestinationFinalize(output) else { throw RenderError(description: "Can't encode \(destination.lastPathComponent)") }
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
    }

    /// Only the apple_desktop tags carry over. Size and orientation tags describe the source pixels,
    /// not the render.
    static func appleDesktopTags(of source: CGImageSource, at index: Int) throws -> CGMutableImageMetadata? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else { return nil }
        let kept = tags.filter { CGImageMetadataTagCopyNamespace($0) as String? == appleDesktop }
        guard !kept.isEmpty else { return nil }
        let result = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(result, appleDesktop as CFString, "apple_desktop" as CFString, nil),
              kept.allSatisfy({ tag in
                  guard let name = CGImageMetadataTagCopyName(tag) as String? else { return false }
                  return CGImageMetadataSetTagWithPath(result, nil, "apple_desktop:\(name)" as CFString, tag)
              })
        else { throw RenderError(description: "Can't keep the wallpaper's time-of-day schedule") }
        return result
    }
}

/// Frames rendered on `concurrentPerform`'s threads. Every access takes the lock, which is what
/// makes the `@unchecked Sendable` true.
private final class FrameSlots: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Result<CGImage, any Error>?]
    private var filled = 0

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    subscript(index: Int) -> Result<CGImage, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        return slots[index]
    }

    /// Returns how many frames are in, this one included.
    func store(at index: Int, _ frame: Result<CGImage, any Error>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        slots[index] = frame
        filled += 1
        return filled
    }
}
