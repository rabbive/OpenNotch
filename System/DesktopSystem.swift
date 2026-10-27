import AppKit
import OpenNotchCore

/// The macOS surfaces the engine touches, behind one seam so tests drive it with a fake.
@MainActor
public protocol DesktopSystem {
    func displays() -> [DisplaySnapshot]
    func spaces(display: String) -> DisplaySpaces?
    func wallpaper(display: String) -> (url: URL?, options: DesktopOptions)
    func setWallpaper(_ url: URL, options: DesktopOptions, display: String) throws
    func indexPlist() -> Data?
    func appearance() -> Appearance
}

@MainActor
public struct LiveDesktop: DesktopSystem {
    public init() {}

    public func displays() -> [DisplaySnapshot] { DisplayTracker.displays() }

    public func spaces(display: String) -> DisplaySpaces? { SpaceTracker.spaces(display: display) }

    public func wallpaper(display: String) -> (url: URL?, options: DesktopOptions) {
        guard let screen = screen(display) else { return (nil, DesktopOptions()) }
        return (
            NSWorkspace.shared.desktopImageURL(for: screen),
            DesktopOptions(NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
        )
    }

    public func setWallpaper(_ url: URL, options: DesktopOptions, display: String) throws {
        guard let screen = screen(display) else { throw RenderError(description: "Display \(display) is gone") }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options.dictionary)
    }

    public func indexPlist() -> Data? { try? Data(contentsOf: IndexPlist.defaultURL) }

    public func appearance() -> Appearance {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    private func screen(_ uuid: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            DisplayTracker.displayID(of: screen).flatMap(DisplayTracker.uuid(of:)) == uuid
        }
    }
}
