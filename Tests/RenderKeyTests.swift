import OpenNotchCore
import Testing

struct RenderKeyTests {
    let base = RenderKey(
        sourcePath: "/Users/me/Pictures/hill.jpg",
        sourceStamp: "1024-1700000000.0",
        placement: .fill,
        background: .black,
        geometry: BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 78, scale: 2),
        corners: .off,
        band: .black
    )

    @Test func sameInputsGiveTheSameFileName() {
        #expect(base.digest == base.digest)
        #expect(base.digest.hasPrefix("v2-"))
    }

    @Test(arguments: 0..<8)
    func anyChangeGivesANewFileName(field: Int) {
        var changed = base
        switch field {
        case 0: changed.sourcePath = "/Users/me/Pictures/sea.jpg"
        case 1: changed.sourceStamp = "1024-1700000001.0"
        case 2: changed.placement = .fit
        case 3: changed.background = RGBA(red: 1, green: 1, blue: 1)
        case 4: changed.geometry = BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 76, scale: 2)
        case 5: changed.corners = .small
        case 6: changed.band.light = RGBA(red: 1, green: 1, blue: 1)
        default: changed.band.dark = RGBA(red: 1, green: 1, blue: 1)
        }
        #expect(changed.digest != base.digest)
    }
}
