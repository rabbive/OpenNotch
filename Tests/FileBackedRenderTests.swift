import CoreGraphics
import Darwin
import Foundation
import OpenNotchCore
import Testing

/// Renders are kept in mapped files rather than memory. They must be the same pixels, and must not
/// count against the app.
struct FileBackedRenderTests {
    let teal = RGBA(red: 0, green: 0.5, blue: 0.5)
    let silver = RGBA(red: 0.82, green: 0.82, blue: 0.84)

    func bytes(_ image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        // Compare only the pixels each row shows, whatever the row padding.
        return (0..<image.height).flatMap { row in data[(row * image.bytesPerRow)..<(row * image.bytesPerRow + image.width * 4)] }
    }

    /// The same drawing on an ordinary in-memory canvas, the way every render was drawn before.
    func reference(_ source: CGImage, _ geometry: BarGeometry, _ placement: Placement, _ corners: CornerStyle, _ band: RGBA) -> CGImage {
        let context = CGContext(data: nil, width: geometry.pixelWidth, height: geometry.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                space: source.colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let canvas = CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight)
        context.setFillColor(teal.cgColor)
        context.fill(canvas)
        context.interpolationQuality = .high
        context.draw(source, in: placement.rect(for: CGSize(width: source.width, height: source.height), in: canvas.size))
        context.setFillColor(band.cgColor)
        context.addPath(WallpaperRenderer.maskPath(geometry: geometry, corners: corners))
        context.fillPath(using: .evenOdd)
        if corners != .off {
            context.setFillColor(RGBA.black.cgColor)
            context.addPath(WallpaperRenderer.bottomCornersPath(geometry: geometry, corners: corners))
            context.fillPath(using: .evenOdd)
        }
        return context.makeImage()!
    }

    @Test(arguments: [Placement.fill, .fit, .stretch, .center], CornerStyle.allCases)
    func everyPathDrawsTheSamePixelsAsAnInMemoryCanvas(placement: Placement, corners: CornerStyle) throws {
        let geometry = BarGeometry(pixelWidth: 1512, pixelHeight: 982, bandHeight: 64, scale: 2)
        let source = TestImages.quadrants(width: 2400, height: 1600)
        let expected = bytes(reference(source, geometry, placement, corners, silver))
        let rendered = try WallpaperRenderer.render(source, geometry: geometry, placement: placement, background: teal, corners: corners, band: silver)
        let placed = try WallpaperRenderer.place(source, geometry: geometry, placement: placement, background: teal)
        let finished = try WallpaperRenderer.finish(placed, geometry: geometry, corners: corners, band: silver)
        #expect(bytes(rendered) == expected)
        #expect(bytes(finished) == expected)
    }

    @Test func keptRendersLiveInAMappedFileNotMemory() throws {
        // Other suites render in parallel in this process, so the footprint can't be compared before
        // and after. Each kept image's pixels must instead sit in a file mapping, which the system
        // doesn't charge to the app.
        let geometry = BarGeometry(pixelWidth: 3456, pixelHeight: 2234, bandHeight: 74, scale: 2)
        let source = TestImages.quadrants(width: 400, height: 300)
        let kept = [
            try WallpaperRenderer.place(source, geometry: geometry, placement: .fill, background: teal),
            try WallpaperRenderer.render(source, geometry: geometry, placement: .fill, background: teal, corners: .high, band: .black),
        ]
        for image in kept {
            let data = try #require(image.dataProvider?.data)
            let address = UInt64(UInt(bitPattern: CFDataGetBytePtr(data)))
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let length = proc_regionfilename(getpid(), address, &path, UInt32(path.count))
            #expect(length > 0, "a \(image.width)x\(image.height) render is in anonymous memory")
            #expect(String(cString: path).contains("OpenNotch-"), "mapped from \(String(cString: path))")
        }
    }
}
