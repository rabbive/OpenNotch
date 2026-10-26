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
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var statuses: [DisplayStatus] = []
    private(set) var spacesToVisit: [String] = []
    private(set) var startupError: String?
    /// Never saved, so a relaunch always shows the icon and the user can't lock themselves out.
    var isIconVisible = true

    @ObservationIgnored private let engine: NotchEngine?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var wallpaperStoreWatcher: DispatchSourceFileSystemObject?

    private enum Key {
        static let enabled = "enabled"
        static let builtinOnly = "builtinOnly"
        static let corners = "corners"
    }

    init() {
        isEnabled = defaults.bool(forKey: Key.enabled)
        builtinOnly = defaults.object(forKey: Key.builtinOnly) as? Bool ?? true
        corners = defaults.string(forKey: Key.corners).flatMap(CornerStyle.init(rawValue:)) ?? .off
        do {
            engine = NotchEngine(system: LiveDesktop(), store: try Store(directory: Store.defaultDirectory))
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

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("OpenNotch: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Space switches, display changes and wallpaper store writes arrive in bursts; one sync per burst.
    private func scheduleSync(after delay: Duration = .milliseconds(400)) {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let engine else { return }
            engine.sync(enabled: isEnabled, builtinOnly: builtinOnly, corners: corners)
            statuses = engine.statuses
            spacesToVisit = engine.spacesToVisit
        }
    }

    private func observeTriggers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, name) in [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
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
