import Foundation
import OpenNotchCore

/// One line of the menu's status. The title is a few words from a fixed set, so a status never sets the
/// menu's width. Anything longer, such as an error message or a list of Spaces, is the detail, which
/// the menu shows in a submenu.
public struct StatusLine: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    /// About the width of "Bar Color in Light Mode", the menu's widest item.
    public static let maxTitleLength = 24

    public static func lines(
        statuses: [DisplayStatus],
        spacesToVisit: [String],
        painting: RenderProgress?,
        isEnabled: Bool,
        builtinOnly: Bool,
        startupError: String?
    ) -> [StatusLine] {
        if let startupError { return [StatusLine("Can't read saved state", detail: startupError)] }
        var lines: [StatusLine]
        if let painting {
            lines = [StatusLine(painting.frameCount > 1 ? "Painting… \(painting.framesDone) of \(painting.frameCount)" : "Painting wallpaper…")]
        } else if statuses.isEmpty {
            lines = [StatusLine(isEnabled ? (builtinOnly ? "No built-in display" : "No display found") : "Off")]
        } else {
            lines = statuses.map { line($0) }
        }
        if !spacesToVisit.isEmpty {
            lines.append(StatusLine("Visit to restore", detail: "Visit \(spacesToVisit.formatted(.list(type: .and))) to restore the wallpaper."))
        }
        return lines
    }

    /// "MacBook: On". A long display name is cut short to leave room for the status.
    static func line(_ display: DisplayStatus) -> StatusLine {
        let (summary, detail) = Self.summary(display.status)
        let room = maxTitleLength - summary.count - 2
        let name = display.isBuiltin ? "MacBook" : display.name.count > room ? String(display.name.prefix(room - 1)) + "…" : display.name
        return StatusLine("\(name): \(summary)", detail: detail.map { display.isBuiltin ? $0 : "\(display.name): \($0)" })
    }

    static func summary(_ status: NotchStatus) -> (String, String?) {
        switch status {
        case .off: ("Off", nil)
        case .applied: ("On", nil)
        case .fullScreenSpace: ("Paused", "Full-screen apps show no wallpaper. OpenNotch paints again on a desktop.")
        case .unsupportedWallpaper: ("Not supported", "OpenNotch can't paint Apple's wallpaper collections, aerials, or Photos shuffles yet.")
        case .failed(let message): ("Couldn't apply", message)
        }
    }
}
