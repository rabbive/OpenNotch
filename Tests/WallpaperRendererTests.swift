import CoreGraphics
import ImageIO
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
    func roundingBlackensAllFourCorners(corners: CornerStyle) throws {
        let pixels = TestImages.Pixels(try render(corners: corners))
        let below = geometry.bandHeight
        for (x, y) in [(0, below), (159, below), (0, 99), (159, 99)] {
            #expect(pixels[x, y] == black, "corner pixel \(x),\(y) is \(pixels[x, y])")
        }
        for (x, y) in [(80, below), (80, 99), (0, 50), (159, 50)] {
            #expect(pixels[x, y] != black, "edge pixel \(x),\(y) is black")
        }
    }

    @Test func bottomCornersStayBlackUnderAColoredBand() throws {
        let pixels = TestImages.Pixels(try render(corners: .medium, band: silver))
        for x in [0, 159] {
            #expect(zip(pixels[x, geometry.bandHeight], [209, 209, 214]).allSatisfy { abs(Int($0) - $1) <= 1 }, "top corner at x \(x) is \(pixels[x, geometry.bandHeight])")
            #expect(pixels[x, 99] == black, "bottom corner at x \(x) is \(pixels[x, 99])")
        }
    }

    @Test func squareCornersLeaveTheWallpaper() throws {
        let pixels = TestImages.Pixels(try render(corners: .off))
        #expect(pixels[0, geometry.bandHeight] == [255, 0, 0])
        #expect(pixels[0, 99] == [0, 0, 255])
        #expect(pixels[159, 99] == [255, 255, 255])
    }

    @Test func largerRadiusRoundsDeeper() throws {
        for probe in [(x: 5, y: geometry.bandHeight + 5), (x: 154, y: 94)] {
            #expect(TestImages.Pixels(try render(corners: .small))[probe.x, probe.y] != black)
            #expect(TestImages.Pixels(try render(corners: .high))[probe.x, probe.y] == black)
        }
    }

    @Test func fitLetterboxesWithTheFillColor() throws {
        let pixels = TestImages.Pixels(try render(.fit))
        for x in [1, 158] {
            let pixel = pixels[x, 50]
            #expect(pixel[0] == 0 && abs(Int(pixel[1]) - 128) <= 1 && abs(Int(pixel[2]) - 128) <= 1, "letterbox at x \(x) is \(pixel)")
        }
    }

    /// A 1600 × 1200 photo with the quadrants' layout.
    func photo() throws -> CGImageSource {
        try TestImages.source(TestImages.quadrants(width: 1600, height: 1200))
    }

    @Test(arguments: [Placement.fill, .fit, .stretch])
    func aLargePhotoDecodesAtTheSizeItIsShown(placement: Placement) throws {
        let image = try WallpaperRenderer.load(photo(), at: 0, for: geometry, placement: placement)
        let shown = placement.rect(for: CGSize(width: 1600, height: 1200), in: CGSize(width: 160, height: 100))
        let scale = Double(max(shown.width / 1600, shown.height / 1200))
        #expect(abs(Double(image.width) - 1600 * scale) <= 1, "decoded \(image.width)x\(image.height)")
        #expect(abs(Double(image.height) - 1200 * scale) <= 1, "decoded \(image.width)x\(image.height)")
    }

    @Test func centeredAndSmallPhotosDecodeInFull() throws {
        let centered = try WallpaperRenderer.load(photo(), at: 0, for: geometry, placement: .center)
        #expect(centered.width == 1600 && centered.height == 1200)
        let small = try WallpaperRenderer.load(TestImages.source(TestImages.quadrants()), at: 0, for: geometry, placement: .fill)
        #expect(small.width == 40 && small.height == 30)
    }

    @Test(arguments: [Placement.fill, .fit, .stretch])
    func aLargePhotoLandsWhereAFullDecodeDoes(placement: Placement) throws {
        let source = try photo()
        func draw(_ image: CGImage) throws -> TestImages.Pixels {
            TestImages.Pixels(try WallpaperRenderer.render(image, geometry: geometry, placement: placement, background: teal, corners: .medium, band: .black))
        }
        let screenSized = try draw(WallpaperRenderer.load(source, at: 0, for: geometry, placement: placement))
        let full = try draw(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        // Where quadrants or the photo's edges meet, the two resample a little differently.
        let shown = placement.rect(for: CGSize(width: 1600, height: 1200), in: CGSize(width: 160, height: 100))
        let seamColumns = [shown.minX, shown.midX, shown.maxX].map { Double($0) }
        let seamRows = [shown.minY, shown.midY, shown.maxY].map { 100 - Double($0) }
        for y in 0..<100 where seamRows.allSatisfy({ abs(Double(y) - $0) > 2 }) {
            for x in 0..<160 where seamColumns.allSatisfy({ abs(Double(x) - $0) > 2 }) {
                let (a, b) = (screenSized[x, y], full[x, y])
                #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 8 }, "pixel \(x),\(y) is \(a), full decode \(b)")
            }
        }
    }
}
