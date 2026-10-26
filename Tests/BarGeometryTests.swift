import CoreGraphics
import OpenNotchCore
import Testing

struct BarGeometryTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let frame: CGRect
        let visibleTop: CGFloat
        let safeAreaTop: CGFloat
        let scale: CGFloat
        let expected: BarGeometry
        var testDescription: String { name }
    }

    @Test(arguments: [
        Case(
            name: "14-inch MacBook Pro, menu bar shown",
            frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), visibleTop: 1290, safeAreaTop: 38, scale: 2,
            expected: BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 78, scale: 2)
        ),
        Case(
            name: "notch, menu bar hidden automatically",
            frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), visibleTop: 1329, safeAreaTop: 38, scale: 2,
            expected: BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 76, scale: 2)
        ),
        Case(
            name: "external 1x display without a notch",
            frame: CGRect(x: 2056, y: 0, width: 1920, height: 1080), visibleTop: 1055, safeAreaTop: 0, scale: 1,
            expected: BarGeometry(pixelWidth: 1920, pixelHeight: 1080, bandHeight: 25, scale: 1)
        ),
        Case(
            name: "no notch, menu bar hidden",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleTop: 900, safeAreaTop: 0, scale: 2,
            expected: BarGeometry(pixelWidth: 2880, pixelHeight: 1800, bandHeight: 0, scale: 2)
        ),
    ])
    func bandMatchesTheMenuBar(_ c: Case) {
        var visible = c.frame
        visible.size.height = c.visibleTop - c.frame.minY
        let geometry = BarGeometry(frame: c.frame, visibleFrame: visible, safeAreaTop: c.safeAreaTop, scale: c.scale)
        #expect(geometry == c.expected)
    }
}
