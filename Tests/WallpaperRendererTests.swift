import CoreGraphics
import OpenNotchCore
import Testing

struct WallpaperRendererTests {
    let geometry = BarGeometry(pixelWidth: 160, pixelHeight: 100, bandHeight: 8, scale: 2)
    let teal = RGBA(red: 0, green: 0.5, blue: 0.5)
    let silver = RGBA(red: 0.82, green: 0.82, blue: 0.84)
    let black: [UInt8] = [0, 0, 0]

    func render(_ placement: Placement = .fill, corners: CornerStyle = .off, band: RGBA = .black) throws -> CGImage {
        try WallpaperRenderer.render(TestImages.quadrants(), geometry: geometry, placement: placement, background: teal, corners: corners, band: band)
    }

    @Test(arguments: CornerStyle.allCases)
    func fillMatchesGolden(corners: CornerStyle) throws {
        try Golden.check(render(corners: corners), "fill-corners-\(corners.rawValue)")
    }

    @Test func aColoredBandMatchesGolden() throws {
        try Golden.check(render(corners: .medium, band: silver), "band-silver-corners-medium")
    }

    @Test func aColoredBandIsThatColorEdgeToEdge() throws {
        let pixels = TestImages.Pixels(try render(band: silver))
        let expected = [209, 209, 214]
        for y in 0..<geometry.bandHeight {
            for x in 0..<geometry.pixelWidth {
                #expect(zip(pixels[x, y], expected).allSatisfy { abs(Int($0) - $1) <= 1 }, "band pixel \(x),\(y) is \(pixels[x, y])")
            }
        }
        #expect(pixels[40, geometry.bandHeight] == [255, 0, 0])
    }

    @Test(arguments: [Placement.fit, .stretch, .center])
    func placementMatchesGolden(placement: Placement) throws {
        try Golden.check(render(placement), "placement-\(placement.rawValue)")
    }

    @Test(arguments: CornerStyle.allCases)
    func bandIsPureBlackEdgeToEdge(corners: CornerStyle) throws {
        let image = try render(corners: corners)
        #expect(image.width == 160 && image.height == 100)
        let pixels = TestImages.Pixels(image)
        for y in 0..<geometry.bandHeight {
            for x in 0..<geometry.pixelWidth {
                #expect(pixels[x, y] == black, "band pixel \(x),\(y)")
            }
        }
    }

    @Test func wallpaperStartsRightBelowTheBand() throws {
        let pixels = TestImages.Pixels(try render())
        #expect(pixels[40, geometry.bandHeight] == [255, 0, 0])
        #expect(pixels[120, geometry.bandHeight] == [0, 255, 0])
    }

    @Test(arguments: [CornerStyle.small, .medium, .high])
    func roundingBlackensOnlyTheTopCorners(corners: CornerStyle) throws {
        let pixels = TestImages.Pixels(try render(corners: corners))
        let below = geometry.bandHeight
        #expect(pixels[0, below] == black)
        #expect(pixels[159, below] == black)
        #expect(pixels[80, below] != black)
        #expect(pixels[0, 99] != black)
    }

    @Test func squareCornersLeaveTheWallpaper() throws {
        let pixels = TestImages.Pixels(try render(corners: .off))
        #expect(pixels[0, geometry.bandHeight] == [255, 0, 0])
    }

    @Test func largerRadiusRoundsDeeper() throws {
        let probe = (x: 5, y: geometry.bandHeight + 5)
        #expect(TestImages.Pixels(try render(corners: .small))[probe.x, probe.y] != black)
        #expect(TestImages.Pixels(try render(corners: .high))[probe.x, probe.y] == black)
    }

    @Test func fitLetterboxesWithTheFillColor() throws {
        let pixels = TestImages.Pixels(try render(.fit))
        for x in [1, 158] {
            let pixel = pixels[x, 50]
            #expect(pixel[0] == 0 && abs(Int(pixel[1]) - 128) <= 1 && abs(Int(pixel[2]) - 128) <= 1, "letterbox at x \(x) is \(pixel)")
        }
    }
}
