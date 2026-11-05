import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderError: LocalizedError, CustomStringConvertible {
    public let description: String
    public var errorDescription: String? { description }

    public init(description: String) {
        self.description = description
    }
}

/// A wallpaper `WallpaperRenderer.place` drew, and the inputs it drew it from.
public struct PlacedWallpaper: @unchecked Sendable {
    // @unchecked because CGImage is immutable, so threads can share one.
    public let key: RenderKey
    public let image: CGImage

    public init(key: RenderKey, image: CGImage) {
        self.key = key
        self.image = image
    }
}

public enum WallpaperRenderer {
    /// Draws `source` the way macOS would place it on a `geometry`-sized screen, then paints the
    /// band and the rounded top corners in `band`, and the rounded bottom corners in black, the bezel's
    /// color. The result matches the screen pixel for pixel, so the
    /// system shows it unscaled whatever placement option it is set with.
    public static func render(
        _ source: CGImage,
        geometry: BarGeometry,
        placement: Placement,
        background: RGBA,
        corners: CornerStyle,
        band: RGBA
    ) throws -> CGImage {
        // One canvas, so a render holds one screen of pixels rather than the two `finish(place(...))` would.
        // The pool frees the canvas on return, not whenever the calling thread next drains one.
        try autoreleasepool {
            let context = try canvas(geometry, colorSpace: source.colorSpace)
            draw(source, on: context, geometry: geometry, placement: placement, background: background)
            paint(context, geometry: geometry, corners: corners, band: band)
            return try fileBacked(context)
        }
    }

    /// `source` on a `geometry`-sized screen with no band or corners. Decoding and scaling the source
    /// are most of a render's time, and a change of corners or band color leaves this unchanged.
    /// The result is file-backed (see `fileBacked`), so a caller can keep it for a later `finish`
    /// without holding a screen of memory.
    public static func place(_ source: CGImage, geometry: BarGeometry, placement: Placement, background: RGBA) throws -> CGImage {
        try autoreleasepool {
            let context = try canvas(geometry, colorSpace: source.colorSpace)
            draw(source, on: context, geometry: geometry, placement: placement, background: background)
            return try fileBacked(context)
        }
    }

    /// Paints the band and corners over a wallpaper `place` drew for the same `geometry`.
    public static func finish(_ placed: CGImage, geometry: BarGeometry, corners: CornerStyle, band: RGBA) throws -> CGImage {
        let context = try canvas(geometry, colorSpace: placed.colorSpace)
        context.draw(placed, in: CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight))
        paint(context, geometry: geometry, corners: corners, band: band)
        return try image(of: context)
    }

    private static func draw(_ source: CGImage, on context: CGContext, geometry: BarGeometry, placement: Placement, background: RGBA) {
        let canvas = CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight)
        context.setFillColor(background.cgColor)
        context.fill(canvas)
        context.interpolationQuality = .high
        context.draw(source, in: placement.rect(for: CGSize(width: source.width, height: source.height), in: canvas.size))
    }

    private static func paint(_ context: CGContext, geometry: BarGeometry, corners: CornerStyle, band: RGBA) {
        context.setFillColor(band.cgColor)
        context.addPath(maskPath(geometry: geometry, corners: corners))
        context.fillPath(using: .evenOdd)
        if corners != .off {
            context.setFillColor(RGBA.black.cgColor)
            context.addPath(bottomCornersPath(geometry: geometry, corners: corners))
            context.fillPath(using: .evenOdd)
        }
    }

    private static func canvas(_ geometry: BarGeometry, colorSpace: CGColorSpace?) throws -> CGContext {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: geometry.pixelWidth,
            height: geometry.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw RenderError(description: "Can't create a \(geometry.pixelWidth)x\(geometry.pixelHeight) canvas") }
        return context
    }

    private static func image(of context: CGContext) throws -> CGImage {
        guard let image = context.makeImage() else { throw RenderError(description: "Can't finish the render") }
        return image
    }

    /// The context's pixels, byte for byte, in an image backed by a mapped temporary file instead of
    /// memory. Its pages are clean, so they don't count against the app and the system can drop and
    /// reread them, which lets the engine keep a placed screen and the HEIC encoder hold every frame
    /// until it finalizes without a screen of memory each: on a 16-inch MacBook Pro the app holds
    /// 14 MB rather than 43 MB after a still, and an 8-frame 6K dynamic render peaks at 108 MB, not 330.
    /// The file is unlinked once mapped, so nothing is left on disk when the image goes. If the
    /// file can't be written, the image stays in memory.
    static func fileBacked(_ context: CGContext) throws -> CGImage {
        guard let data = context.data, let space = context.colorSpace else { return try image(of: context) }
        let url = FileManager.default.temporaryDirectory.appending(path: "OpenNotch-\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? Data(bytesNoCopy: data, count: context.bytesPerRow * context.height, deallocator: .none).write(to: url)) != nil,
              let mapped = try? Data(contentsOf: url, options: .alwaysMapped),
              let provider = CGDataProvider(data: mapped as CFData),
              let image = CGImage(
                  width: context.width,
                  height: context.height,
                  bitsPerComponent: context.bitsPerComponent,
                  bitsPerPixel: context.bitsPerPixel,
                  bytesPerRow: context.bytesPerRow,
                  space: space,
                  bitmapInfo: context.bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return try image(of: context) }
        return image
    }

    /// The canvas minus a rounded rect that starts under the band and runs off the bottom edge,
    /// so even-odd filling paints the band and only the two top corners.
    public static func maskPath(geometry: BarGeometry, corners: CornerStyle) -> CGPath {
        let width = CGFloat(geometry.pixelWidth)
        let height = CGFloat(geometry.pixelHeight)
        let below = height - CGFloat(geometry.bandHeight)
        let radius = cornerRadius(geometry: geometry, corners: corners)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        path.addRoundedRect(
            in: CGRect(x: 0, y: -radius, width: width, height: below + radius),
            cornerWidth: radius,
            cornerHeight: radius
        )
        return path
    }

    /// The canvas minus a rounded rect that runs off the top edge, so even-odd filling paints only
    /// the two bottom corners.
    public static func bottomCornersPath(geometry: BarGeometry, corners: CornerStyle) -> CGPath {
        let width = CGFloat(geometry.pixelWidth)
        let height = CGFloat(geometry.pixelHeight)
        let radius = cornerRadius(geometry: geometry, corners: corners)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: width, height: height + radius),
            cornerWidth: radius,
            cornerHeight: radius
        )
        return path
    }

    /// In pixels, small enough that the top and bottom corners never meet below the band.
    static func cornerRadius(geometry: BarGeometry, corners: CornerStyle) -> CGFloat {
        let width = CGFloat(geometry.pixelWidth)
        let below = CGFloat(geometry.pixelHeight - geometry.bandHeight)
        return max(0, min(CGFloat(corners.radius * geometry.scale), width / 2, below / 2))
    }

    public static func load(_ url: URL, for geometry: BarGeometry, placement: Placement) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { throw RenderError(description: "Can't read \(url.lastPathComponent)") }
        return try load(source, at: CGImageSourceGetPrimaryImageIndex(source), for: geometry, placement: placement)
    }

    /// Decodes no more pixels than the frame covers once placed on a `geometry`-sized screen, so a 6K
    /// photo costs about what the screen does and `render` draws it at about 1:1. Center shows the
    /// source pixel for pixel, and a frame smaller than the screen has nothing to spare, so those decode in full.
    public static func load(_ source: CGImageSource, at index: Int, for geometry: BarGeometry, placement: Placement) throws -> CGImage {
        let full = { () throws -> CGImage in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil)
            else { throw RenderError(description: "Can't read frame \(index)") }
            return image
        }
        guard placement != .center,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return try full() }
        let size = CGSize(width: width, height: height)
        let placed = placement.rect(for: size, in: CGSize(width: geometry.pixelWidth, height: geometry.pixelHeight))
        let scale = max(placed.width / size.width, placed.height / size.height)
        // Rounding error alone must not ask for one pixel more than the screen shows.
        let longestSide = Int((max(size.width, size.height) * scale - 0.001).rounded(.up))
        guard longestSide < max(width, height) else { return try full() }
        // Without the transform option the thumbnail keeps the orientation a full decode has, so both place alike.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        else { throw RenderError(description: "Can't read frame \(index)") }
        return image
    }

    /// Writes beside the destination and renames, so a crash never leaves a half-written wallpaper.
    /// The file type follows the extension.
    public static func write(_ image: CGImage, to url: URL) throws {
        guard let type = UTType(filenameExtension: url.pathExtension)
        else { throw RenderError(description: "Can't write \(url.lastPathComponent)") }
        let partial = url.appendingPathExtension("partial")
        guard let destination = CGImageDestinationCreateWithURL(partial as CFURL, type.identifier as CFString, 1, nil)
        else { throw RenderError(description: "Can't write \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError(description: "Can't encode \(url.lastPathComponent)") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
    }
}
