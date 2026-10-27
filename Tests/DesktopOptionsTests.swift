import AppKit
import OpenNotchCore
import OpenNotchSystem
import Testing

struct DesktopOptionsTests {
    @Test func originalOptionsSurviveARelaunch() throws {
        let color = NSColor(calibratedRed: 0.2549, green: 0.4118, blue: 0.6667, alpha: 1)
        let original: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: 3),
            .allowClipping: NSNumber(value: true),
            .fillColor: color,
        ]
        let saved = try JSONEncoder().encode(DesktopOptions(original))
        let restored = try JSONDecoder().decode(DesktopOptions.self, from: saved).dictionary
        #expect(restored[.imageScaling] as? NSNumber == 3)
        #expect(restored[.allowClipping] as? NSNumber == true)
        #expect(restored[.fillColor] as? NSColor == color)
    }

    @Test func missingKeysStayMissing() {
        #expect(DesktopOptions([:]).dictionary.isEmpty)
    }

    @Test(arguments: [
        (UInt?.none, Bool?.none, Placement.fill),
        (3, true, .fill),
        (3, false, .fit),
        (1, nil, .stretch),
        (2, nil, .center),
    ])
    func placementFollowsTheScalingOption(scaling: UInt?, clipping: Bool?, expected: Placement) {
        #expect(DesktopOptions(scaling: scaling, allowClipping: clipping).placement == expected)
    }
}
