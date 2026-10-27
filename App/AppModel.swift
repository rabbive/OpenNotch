import AppKit
import Observation
import OpenNotchCore
import OpenNotchSystem
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private(set) var isEnabled: Bool
    private(set) var builtinOnly: Bool
    private(set) var corners: CornerStyle
    private(set) var lightBand: BandColor
    private(set) var darkBand: BandColor
    private(set) var launchAtLogin = AppModel.launchesAtLogin
    private(set) var startupError: String?
    /// Never saved, so a relaunch always shows the icon and the user can't lock themselves out.
    var isIconVisible = true

    @ObservationIgnored private let engine: NotchEngine?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var wallpaperStoreWatcher: DispatchSourceFileSystemObject?

    var statuses: [DisplayStatus] { engine?.statuses ?? [] }
    var spacesToVisit: [String] { engine?.spacesToVisit ?? [] }
    var painting: RenderProgress? { engine?.painting }

    private enum Key {
        static let enabled = "enabled"
        static let builtinOnly = "builtinOnly"
        static let corners = "corners"
        static let lightBand = "lightBand"
        static let darkBand = "darkBand"
    }

    init() {
        isEnabled = defaults.bool(forKey: Key.enabled)
        builtinOnly = defaults.object(forKey: Key.builtinOnly) as? Bool ?? true
        corners = defaults.string(forKey: Key.corners).flatMap(CornerStyle.init(rawValue:)) ?? .off
        lightBand = defaults.string(forKey: Key.lightBand).flatMap(BandColor.init(rawValue:)) ?? .black
        darkBand = defaults.string(forKey: Key.darkBand).flatMap(BandColor.init(rawValue:)) ?? .black
        do {
            let desktop = LiveDesktop()
            let store = try Store(directory: Store.defaultDirectory) {
                guard let index = desktop.indexPlist() else { return nil }
                let displays = desktop.displays()
                let spaces = Dictionary(displays.compactMap { display in
                    desktop.spaces(display: display.uuid).map { (display.uuid, $0.all.filter(\.isDesktop).map(\.uuid)) }
                }, uniquingKeysWith: { first, _ in first })
                guard !displays.isEmpty, spaces.count == displays.count else { return IndexPlist.imageURLs(in: index) }
                return IndexPlist.imageURLs(in: index, desktopSpacesByDisplay: spaces)
            }
            engine = NotchEngine(system: desktop, store: store)
        } catch {
            engine = nil
            startupError = "Can't read saved state: \(error.localizedDescription)"
        }
        observeTriggers()
        scheduleSync(after: .zero)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        scheduleSync(after: .zero)
    }

    func setBuiltinOnly(_ on: Bool) {
        builtinOnly = on
        defaults.set(on, forKey: Key.builtinOnly)
        scheduleSync(after: .zero)
    }

    func setCorners(_ style: CornerStyle) {
        corners = style
        defaults.set(style.rawValue, forKey: Key.corners)
        scheduleSync(after: .zero)
    }

    func setBand(_ color: BandColor, for appearance: Appearance) {
        switch appearance {
        case .light: lightBand = color
        case .dark: darkBand = color
        }
        defaults.set(color.rawValue, forKey: appearance == .light ? Key.lightBand : Key.darkBand)
        scheduleSync(after: .zero)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("OpenNotch: launch at login change failed: \(error)")
        }
        // macOS can hold a new login item until the user allows it in System Settings.
        if on && SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = Self.launchesAtLogin
    }

    nonisolated private static var launchesAtLogin: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    /// Space switches, display changes and wallpaper store writes arrive in bursts; one sync per burst.
    private func scheduleSync(after delay: Duration = .milliseconds(400)) {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let engine else { return }
            await engine.sync(
                enabled: isEnabled,
                builtinOnly: builtinOnly,
                corners: corners,
                band: BandColors(light: lightBand.rgba, dark: darkBand.rgba)
            )
        }
    }

    private func observeTriggers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, name) in [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            // Posted on every light and dark switch, including automatic ones.
            (DistributedNotificationCenter.default() as NotificationCenter, Notification.Name("AppleInterfaceThemeChangedNotification")),
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSync() }
            }
            observers.append((center, token))
        }
        let reopened = NotificationCenter.default.addObserver(forName: AppDelegate.reopened, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isIconVisible = true }
        }
        observers.append((NotificationCenter.default, reopened))
        watchWallpaperStore()
    }

    /// macOS posts nothing public when the wallpaper changes, but it rewrites its store file.
    private func watchWallpaperStore() {
        let directory = IndexPlist.defaultURL.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        wallpaperStoreWatcher = source
    }
}

/// The band colors the menu offers.
enum BandColor: String, CaseIterable {
    case black, graphite, silver, white

    var rgba: RGBA {
        switch self {
        case .black: .black
        case .graphite: RGBA(red: 0.2, green: 0.2, blue: 0.21)
        case .silver: RGBA(red: 0.82, green: 0.82, blue: 0.84)
        case .white: RGBA(red: 1, green: 1, blue: 1)
        }
    }
}
