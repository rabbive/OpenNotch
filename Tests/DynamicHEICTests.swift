import CoreGraphics
import Foundation
import ImageIO
import OpenNotchCore
import Testing
import UniformTypeIdentifiers

/// A small dynamic wallpaper laid out like the ones macOS ships: one solid color per frame, and the
/// apple_desktop schedule on the first frame.
enum DynamicFixture {
    static let appleDesktop = "http://ns.apple.com/namespace/1.0/"
    static let colors = [RGBA(red: 0.8, green: 0.2, blue: 0.2), RGBA(red: 0.2, green: 0.8, blue: 0.2), RGBA(red: 0.2, green: 0.2, blue: 0.8)]
    /// Base64 binary plists, the form macOS stores schedules in.
    static let tags = [
        "solar": schedule(["si": [["i": 0, "z": 90], ["i": 1, "z": 180], ["i": 2, "z": 270]]]),
        "h24": schedule(["ti": [["i": 0, "t": 6], ["i": 1, "t": 12], ["i": 2, "t": 19]]]),
    ]
    static let canEncode = heic([solid(.black)], tags: [:]) != nil

    static func schedule(_ value: [String: Any]) -> String {
        try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).base64EncodedString()
    }

    static func solid(_ color: RGBA, width: Int = 64, height: Int = 64) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func heic(_ frames: [CGImage], tags: [String: String]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.heic.identifier as CFString, frames.count, nil)
        else { return nil }
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(metadata, appleDesktop as CFString, "apple_desktop" as CFString, nil)
        for (name, value) in tags {
            let tag = CGImageMetadataTagCreate(appleDesktop as CFString, "apple_desktop" as CFString, name as CFString, .string, value as CFString)!
            CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:\(name)" as CFString, tag)
        }
        for (index, frame) in frames.enumerated() {
            if index == 0 {
                CGImageDestinationAddImageAndMetadata(destination, frame, metadata, nil)
            } else {
                CGImageDestinationAddImage(destination, frame, nil)
            }
        }
        return CGImageDestinationFinalize(destination) ? Data(referencing: data) : nil
    }

    static func appleDesktopTags(of source: CGImageSource, at index: Int) -> [String: String] {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else { return [:] }
        var found: [String: String] = [:]
        for tag in tags where CGImageMetadataTagCopyNamespace(tag) as String? == appleDesktop {
            if let name = CGImageMetadataTagCopyName(tag) as String?, let value = CGImageMetadataTagCopyValue(tag) as? String {
                found[name] = value
            }
        }
        return found
    }
}

@Suite(.enabled(if: DynamicFixture.canEncode, "This runner can't encode HEIC, so there is no dynamic wallpaper to test with"))
struct DynamicHEICTests {
    let geometry = BarGeometry(pixelWidth: 128, pixelHeight: 80, bandHeight: 10, scale: 2)
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "OpenNotchDynamic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func renderFixture() throws -> CGImageSource {
        let source = folder.appending(path: "dynamic.heic")
        let rendered = folder.appending(path: "rendered.heic")
        let fixture = try #require(DynamicFixture.heic(DynamicFixture.colors.map { DynamicFixture.solid($0) }, tags: DynamicFixture.tags))
        try fixture.write(to: source)
        try DynamicHEIC.render(source, to: rendered, geometry: geometry, placement: .fill, background: .black, corners: .off)
        return try #require(CGImageSourceCreateWithURL(rendered as CFURL, nil))
    }

    @Test func everyFrameKeepsItsPlaceUnderABlackBand() throws {
        let rendered = try renderFixture()
        try #require(CGImageSourceGetCount(rendered) == DynamicFixture.colors.count)
        for (index, color) in DynamicFixture.colors.enumerated() {
            let pixels = TestImages.Pixels(try #require(CGImageSourceCreateImageAtIndex(rendered, index, nil)))
            #expect(pixels.width == geometry.pixelWidth && pixels.height == geometry.pixelHeight)
            // HEIC is lossy, so channels are compared within a tolerance.
            let band = (0..<geometry.bandHeight).flatMap { y in (0..<geometry.pixelWidth).flatMap { x in pixels[x, y] } }
            let brightest = band.map(Int.init).max() ?? 0
            #expect(brightest <= 16, "frame \(index) band reaches \(brightest) per channel")
            let expected = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
            let below = pixels[geometry.pixelWidth / 2, geometry.pixelHeight / 2]
            #expect(zip(below, expected).allSatisfy { abs(Int($0) - $1) <= 24 }, "frame \(index) is \(below), expected \(expected)")
        }
    }

    @Test func theTimeOfDayScheduleSurvives() throws {
        let rendered = try renderFixture()
        #expect(CGImageSourceGetType(rendered) as String? == UTType.heic.identifier)
        #expect(DynamicFixture.appleDesktopTags(of: rendered, at: 0) == DynamicFixture.tags)
    }
}
