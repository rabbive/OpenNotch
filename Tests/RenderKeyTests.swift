import OpenNotchCore
import Testing

struct RenderKeyTests {
    let base = RenderKey(
        sourcePath: "/Users/me/Pictures/hill.jpg",
        sourceStamp: "1024-1700000000.0",
        placement: .fill,
        background: .black,
        geometry: BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 78, scale: 2),
        corners: .off
    )

    @Test func sameInputsGiveTheSameFileName() {
        #expect(base.digest == base.digest)
        #expect(base.digest.hasPrefix("v1-"))
    }

    @Test(arguments: 0..<6)
    func anyChangeGivesANewFileName(field: Int) {
        var changed = base
        switch field {
        case 0: changed.sourcePath = "/Users/me/Pictures/sea.jpg"
        case 1: changed.sourceStamp = "1024-1700000001.0"
        case 2: changed.placement = .fit
        case 3: changed.background = RGBA(red: 1, green: 1, blue: 1)
        case 4: changed.geometry = BarGeometry(pixelWidth: 4112, pixelHeight: 2658, bandHeight: 76, scale: 2)
        default: changed.corners = .small
        }
        #expect(changed.digest != base.digest)
    }
}
