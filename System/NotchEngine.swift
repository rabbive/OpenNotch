import Foundation
import Observation
import OpenNotchCore

public enum NotchStatus: Equatable, Sendable {
    case off
    case applied
    case fullScreenSpace
    case unsupportedWallpaper
    case failed(String)
}

public struct DisplayStatus: Equatable, Sendable {
    public let name: String
    public let status: NotchStatus

    public init(name: String, status: NotchStatus) {
        self.name = name
        self.status = status
    }
}

/// Brings the current Space of every display in line with the settings. Every trigger calls
/// `sync`, and calling it again with nothing changed sets nothing.
@MainActor
@Observable
public final class NotchEngine {
    private let system: DesktopSystem
    private let store: Store

    /// The displays OpenNotch is on for, built-in first, plus any display it failed to restore.
    /// Empty when it is off or no display qualifies.
    public private(set) var statuses: [DisplayStatus] = []
    /// Spaces still showing a render while OpenNotch is off. macOS only lets an app set the wallpaper
    /// of the Space on screen, so each one is restored on the user's next visit.
    public private(set) var spacesToVisit: [String] = []
    /// The render being drawn. Nil whenever none is.
    public private(set) var painting: RenderProgress?

    @ObservationIgnored private var requested: Settings?
    @ObservationIgnored private var running: Task<Void, Never>?

    private struct Settings {
        let enabled: Bool
        let builtinOnly: Bool
        let corners: CornerStyle
        let band: BandColors
    }

    public init(system: DesktopSystem, store: Store) {
        self.system = system
        self.store = store
    }

    /// With `builtinOnly`, external displays are treated as off, so any OpenNotch changed get restored.
    /// Passes never overlap, since a render runs off the main actor: a sync asked for during a pass
    /// waits for it, then the latest settings get one more pass. Returns once every request is applied.
    public func sync(enabled: Bool, builtinOnly: Bool = true, corners: CornerStyle, band: BandColors = .black) async {
        requested = Settings(enabled: enabled, builtinOnly: builtinOnly, corners: corners, band: band)
        if running == nil {
            running = Task {
                while let settings = requested {
                    requested = nil
                    await pass(settings)
                }
                running = nil
            }
        }
        await running?.value
    }

    private func pass(_ settings: Settings) async {
        let displays = system.displays()
        var statuses: [DisplayStatus] = []
        var spacesToVisit: [String] = []
        for display in displays {
            let on = settings.enabled && (display.isBuiltin || !settings.builtinOnly)
            let spaces = system.spaces(display: display.uuid)
            let status: NotchStatus
            do {
                status = try await reconcile(display: display, spaces: spaces, enabled: on, settings: settings)
            } catch {
                status = .failed(String(describing: error))
            }
            if on || status != .off { statuses.append(DisplayStatus(name: display.name, status: status)) }
            if !on { spacesToVisit += labelsOfSpacesToVisit(display: display, spaces: spaces) }
        }
        if !settings.enabled { spacesToVisit += labelsOfDisconnectedDisplays(connected: displays) }
        store.sweep()
        self.statuses = statuses
        self.spacesToVisit = spacesToVisit
    }

    private func reconcile(display: DisplaySnapshot, spaces: DisplaySpaces?, enabled: Bool, settings: Settings) async throws -> NotchStatus {
        if let spaces {
            let live = Set(spaces.all.map(\.uuid))
            try store.forget(store.applied.keys.filter { $0.display == display.uuid && $0.space.map { !live.contains($0) } ?? false })
        }
        if spaces?.current.isDesktop == false { return enabled ? .fullScreenSpace : .off }

        let key = SpaceKey(display: display.uuid, space: spaces?.current.uuid)
        let current = system.wallpaper(display: display.uuid)
        let indexPlist = system.indexPlist()
        // NSWorkspace can report no file or a placeholder, and then the wallpaper store names what is
        // on screen, which may be a render. A render must never be taken for the original.
        let shown = WallpaperSource.resolve(current: current.url, display: display.uuid, space: key.space, indexPlist: indexPlist).url
        let showingRender = shown.map(store.isRender) ?? false
        let renderRecord = shown.flatMap { store.record(forRender: $0) }
        guard !showingRender || renderRecord != nil else {
            return .failed("A render is showing but its original wallpaper wasn't saved")
        }

        if !enabled {
            if let renderRecord, let shown {
                let options = current.url.map { Self.sameFile($0, shown) } == true ? current.options : renderRecord.originalOptions
                try recordOtherSpacesShowing(
                    renderRecord.renderedURL,
                    originalURL: renderRecord.originalURL,
                    options: options,
                    display: display.uuid,
                    currentSpace: key.space,
                    spaces: spaces,
                    indexPlist: indexPlist
                )
                try system.setWallpaper(renderRecord.originalURL, options: options, display: display.uuid)
            }
            try store.forget([key])
            return .off
        }

        let original: (url: URL?, options: DesktopOptions)
        if let renderRecord, let shown {
            // Renders are set with the original options, so other options reported with one are the user's new choice.
            original = (renderRecord.originalURL, current.url.map { Self.sameFile($0, shown) } == true ? current.options : renderRecord.originalOptions)
        } else {
            original = current
        }

        let source: URL
        let isDynamic: Bool
        switch WallpaperSource.resolve(current: original.url, display: display.uuid, space: key.space, indexPlist: indexPlist) {
        case .image(let url):
            (source, isDynamic) = (url, false)
        case .dynamic(let url):
            (source, isDynamic) = (url, true)
        case .unsupported:
            if !showingRender { try store.forget([key]) }
            return .unsupportedWallpaper
        }

        let renderKey = RenderKey(
            sourcePath: source.path,
            sourceStamp: try Self.stamp(source),
            placement: original.options.placement,
            background: original.options.background,
            geometry: display.geometry,
            corners: settings.corners,
            // A still or a time-of-day wallpaper shows every frame under the current appearance, and
            // an appearance change re-syncs, so it gets one color. A light-and-dark one gets both.
            band: isDynamic && DynamicHEIC.switchesWithAppearance(source)
                ? settings.band
                : BandColors(settings.band[system.appearance()])
        )
        let rendered = store.rendersDirectory.appending(path: "\(renderKey.digest).\(isDynamic ? "heic" : "png")")
        if !FileManager.default.fileExists(atPath: rendered.path) {
            try await paint(source, to: rendered, isDynamic: isDynamic, key: renderKey)
            // The user can switch Spaces or pick another wallpaper while it draws; start over from what is on screen.
            let now = system.wallpaper(display: display.uuid)
            let spacesNow = system.spaces(display: display.uuid)
            if spacesNow?.current.uuid != key.space || now.url != current.url || now.options != current.options {
                return try await reconcile(display: display, spaces: spacesNow, enabled: enabled, settings: settings)
            }
        }
        // Recorded first: a crash after the set would otherwise leave a render on screen that no
        // record names, which the next launch's sweep deletes along with the way back.
        try store.record(AppliedWallpaper(key: key, originalURL: source, originalOptions: original.options, renderedURL: rendered))
        if shown?.path != rendered.path {
            try system.setWallpaper(rendered, options: original.options, display: display.uuid)
        }
        return .applied
    }

    /// Draws off the main actor, since a dynamic wallpaper can take seconds, and keeps `painting` current.
    /// Utility priority, so a paint yields to whatever the user is doing instead of competing with it.
    private func paint(_ source: URL, to rendered: URL, isDynamic: Bool, key: RenderKey) async throws {
        painting = RenderProgress()
        defer { painting = nil }
        let (updates, continuation) = AsyncStream.makeStream(of: RenderProgress.self)
        let work = Task.detached(priority: .utility) {
            defer { continuation.finish() }
            if isDynamic {
                try DynamicHEIC.render(
                    source,
                    to: rendered,
                    geometry: key.geometry,
                    placement: key.placement,
                    background: key.background,
                    corners: key.corners,
                    band: key.band
                ) { continuation.yield($0) }
            } else {
                let image = try WallpaperRenderer.render(
                    WallpaperRenderer.load(source, for: key.geometry, placement: key.placement),
                    geometry: key.geometry,
                    placement: key.placement,
                    background: key.background,
                    corners: key.corners,
                    band: key.band.light
                )
                try WallpaperRenderer.writePNG(image, to: rendered)
            }
        }
        for await update in updates { painting = update }
        try await work.value
    }

    private func recordOtherSpacesShowing(
        _ renderedURL: URL,
        originalURL: URL,
        options: DesktopOptions,
        display: String,
        currentSpace: String?,
        spaces: DisplaySpaces?,
        indexPlist: Data?
    ) throws {
        guard let spaces, let indexPlist else { return }
        for space in spaces.all where space.isDesktop && space.uuid != currentSpace {
            guard let shown = IndexPlist.imageURL(in: indexPlist, display: display, space: space.uuid),
                  Self.sameFile(shown, renderedURL)
            else { continue }
            try store.record(AppliedWallpaper(
                key: SpaceKey(display: display, space: space.uuid),
                originalURL: originalURL,
                originalOptions: options,
                renderedURL: renderedURL
            ))
        }
    }

    private static func sameFile(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Built-in Spaces keep their v0.1 labels; the others name their display.
    private func labelsOfSpacesToVisit(display: DisplaySnapshot, spaces: DisplaySpaces?) -> [String] {
        let numbers = Dictionary((spaces?.all ?? []).map { ($0.uuid, $0.number) }, uniquingKeysWith: { first, _ in first })
        let suffix = display.isBuiltin ? "" : " on \(display.name)"
        return store.applied.keys
            .filter { $0.display == display.uuid && $0.space != spaces?.current.uuid }
            .map { key in key.space.flatMap { numbers[$0] ?? nil } }
            .sorted { ($0 ?? .max) < ($1 ?? .max) }
            .map { number in number.map { "Desktop \($0)\(suffix)" } ?? (display.isBuiltin ? "Built-in display" : display.name) }
    }

    /// Records outlive a disconnected display, so reconnecting it while off restores it.
    private func labelsOfDisconnectedDisplays(connected: [DisplaySnapshot]) -> [String] {
        let count = Set(store.applied.keys.map(\.display)).subtracting(connected.map(\.uuid)).count
        switch count {
        case 0: return []
        case 1: return ["a disconnected display"]
        default: return ["\(count) disconnected displays"]
        }
    }

    static func stamp(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(modified)"
    }
}
