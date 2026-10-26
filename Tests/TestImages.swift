import CoreGraphics
import Foundation
import OpenNotchCore
import Testing

enum TestImages {
    /// Red and green across the top half, blue and white across the bottom.
    static func quadrants(width: Int = 40, height: Int = 30) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let w = CGFloat(width) / 2, h = CGFloat(height) / 2
        for (color, rect) in [
            (RGBA(red: 1, green: 0, blue: 0), CGRect(x: 0, y: h, width: w, height: h)),
            (RGBA(red: 0, green: 1, blue: 0), CGRect(x: w, y: h, width: w, height: h)),
            (RGBA(red: 0, green: 0, blue: 1), CGRect(x: 0, y: 0, width: w, height: h)),
            (RGBA(red: 1, green: 1, blue: 1), CGRect(x: w, y: 0, width: w, height: h)),
        ] {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        return context.makeImage()!
    }

    /// sRGB RGBA bytes, top row first.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.bytes = bytes
        }

        subscript(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<offset + 3])
        }
    }
}

enum Golden {
    /// Compares against Tests/Goldens/<name>.png. Run `RECORD_GOLDENS=1 swift test` to rewrite them.
    /// The tolerance absorbs resampling differences between macOS releases, not layout changes.
    static func check(_ image: CGImage, _ name: String, tolerance: Int = 4, filePath: String = #filePath) throws {
        if ProcessInfo.processInfo.environment["RECORD_GOLDENS"] == "1" {
            let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().appending(path: "Goldens")
            try WallpaperRenderer.writePNG(image, to: directory.appending(path: "\(name).png"))
            return
        }
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Goldens"),
            "No golden named \(name). Record it with RECORD_GOLDENS=1 swift test."
        )
        let expected = TestImages.Pixels(try WallpaperRenderer.load(url))
        let actual = TestImages.Pixels(image)
        try #require(actual.width == expected.width && actual.height == expected.height, "\(name) changed size")
        let worst = zip(actual.bytes, expected.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= tolerance, "\(name) differs from its golden by up to \(worst) per channel")
    }
}
