import OpenNotchCore
import OpenNotchSystem
import Testing

/// The menu is as wide as its widest line, so a status must never be the widest.
struct StatusLineTests {
    static let reason = "This desktop shows a wallpaper OpenNotch painted, but not which wallpaper it painted over. Choose your wallpaper again in System Settings."

    @Test(arguments: [NotchStatus.off, .applied, .fullScreenSpace, .unsupportedWallpaper, .failed(reason)])
    func noDisplayStatusIsWiderThanTheMenu(status: NotchStatus) {
        let lines = StatusLine.lines(
            statuses: [
                DisplayStatus(name: "Built-in Retina Display", isBuiltin: true, status: status),
                DisplayStatus(name: "LG UltraFine 5K Display (2)", isBuiltin: false, status: status),
                DisplayStatus(name: "LG", isBuiltin: false, status: status),
            ],
            spacesToVisit: ["Desktop 2", "Desktop 3 on LG UltraFine 5K Display (2)", "2 disconnected displays"],
            painting: nil,
            isEnabled: true,
            builtinOnly: false,
            startupError: nil
        )
        #expect(lines.count == 4)
        for line in lines {
            #expect(line.title.count <= StatusLine.maxTitleLength, "\(line.title)")
        }
    }

    @Test func aFailureKeepsItsReasonInTheDetail() {
        let lines = StatusLine.lines(
            statuses: [DisplayStatus(name: "Built-in Retina Display", isBuiltin: true, status: .failed(Self.reason))],
            spacesToVisit: [],
            painting: nil,
            isEnabled: true,
            builtinOnly: true,
            startupError: nil
        )
        #expect(lines == [StatusLine("MacBook: Couldn't apply", detail: Self.reason)])
    }

    @Test func spacesToVisitAreNamedInTheDetail() {
        let lines = StatusLine.lines(
            statuses: [],
            spacesToVisit: ["Desktop 2", "Desktop 3"],
            painting: nil,
            isEnabled: false,
            builtinOnly: true,
            startupError: nil
        )
        #expect(lines == [StatusLine("Off"), StatusLine("Visit to restore", detail: "Visit Desktop 2 and Desktop 3 to restore the wallpaper.")])
    }

    @Test func everyOtherStatusIsShortToo() {
        let error = "The data couldn't be read because it isn't in the correct format."
        let lines = [
            StatusLine.lines(statuses: [], spacesToVisit: [], painting: nil, isEnabled: true, builtinOnly: true, startupError: error),
            StatusLine.lines(statuses: [], spacesToVisit: [], painting: RenderProgress(framesDone: 16, frameCount: 16), isEnabled: true, builtinOnly: true, startupError: nil),
            StatusLine.lines(statuses: [], spacesToVisit: [], painting: RenderProgress(), isEnabled: true, builtinOnly: true, startupError: nil),
            StatusLine.lines(statuses: [], spacesToVisit: [], painting: nil, isEnabled: true, builtinOnly: false, startupError: nil),
        ].flatMap { $0 }
        #expect(lines.first == StatusLine("Can't read saved state", detail: error))
        for line in lines {
            #expect(line.title.count <= StatusLine.maxTitleLength, "\(line.title)")
        }
    }
}
