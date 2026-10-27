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
    public let isBuiltin: Bool
    public let status: NotchStatus

    public init(name: String, isBuiltin: Bool, status: NotchStatus) {
        self.name = name
        self.isBuiltin = isBuiltin
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
    /// The still each display last had placed at screen size, so changing corners or band color only
    /// repaints those. It holds a screen of pixels, about 44 MB on a 16-inch MacBook Pro, so it is
    /// dropped `placedLifetime` after the last paint.
    @ObservationIgnored private var placed: [String: PlacedWallpaper] = [:]
    @ObservationIgnored private var forgetPlaced: Task<Void, Never>?
    static let placedLifetime: Duration = .seconds(120)

    private struct Settings {
        let enabled: Bool
        let builtinOnly: Bool
        let corners: CornerStyle
        let band: BandColors
    }

    private struct DesktopRender {
        let key: SpaceKey
        let url: URL
        let origin: RenderOrigin
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
        let targets = system.displays().map { display in
            (display: display, spaces: system.spaces(display: display.uuid), enabled: settings.enabled && (display.isBuiltin || !settings.builtinOnly))
        }
        // A cached placed image is useful only while OpenNotch is enabled on that connected display.
        // Drop disconnected or newly excluded displays now rather than retaining full-resolution images.
        let reusableDisplays = Set(targets.filter(\.enabled).map { $0.display.uuid })
        placed = placed.filter { reusableDisplays.contains($0.key) }
        // Resolve every off desktop while all records are still available. A legacy render on one display may
        // only be traceable through a record for another display that would otherwise be forgotten first.
        let indexPlist = system.indexPlist()
        var offRenders: [SpaceKey: DesktopRender] = [:]
        if let indexPlist {
            for target in targets where !target.enabled {
                offRenders.merge(desktopsShowingRenders(display: target.display, spaces: target.spaces, indexPlist: indexPlist)) { _, new in new }
            }
        }

        var statuses: [DisplayStatus] = []
        var spacesToVisit: [String] = []
        for target in targets {
            let status: NotchStatus
            do {
                status = try await reconcile(display: target.display, spaces: target.spaces, enabled: target.enabled, settings: settings, indexPlist: indexPlist, offRenders: offRenders)
            } catch {
                status = .failed(error.localizedDescription)
            }
            if target.enabled || status != .off { statuses.append(DisplayStatus(name: target.display.name, isBuiltin: target.display.isBuiltin, status: status)) }
            if !target.enabled { spacesToVisit += labelsOfSpacesToVisit(display: target.display, spaces: target.spaces) }
        }
        let displays = targets.map(\.display)
        if !settings.enabled { spacesToVisit += labelsOfDisconnectedDisplays(connected: displays) }
        store.sweep()
        self.statuses = statuses
        self.spacesToVisit = spacesToVisit
    }

    private func reconcile(
        display: DisplaySnapshot,
        spaces: DisplaySpaces?,
        enabled: Bool,
        settings: Settings,
        indexPlist: Data?,
        offRenders: [SpaceKey: DesktopRender]
    ) async throws -> NotchStatus {
        let staleKeys: [SpaceKey]
        if let spaces {
            let live = Set(spaces.all.map(\.uuid))
            staleKeys = store.applied.keys.filter { $0.display == display.uuid && $0.space.map { !live.contains($0) } ?? false }
        } else {
            staleKeys = []
        }
        if enabled { try store.forget(staleKeys) }
        if spaces?.current.isDesktop == false {
            if !enabled {
                recordOffDesktops(offRenders, display: display.uuid, excluding: nil)
                try store.forget(staleKeys)
            }
            return enabled ? .fullScreenSpace : .off
        }

        let key = SpaceKey(display: display.uuid, space: spaces?.current.uuid)
        let current = system.wallpaper(display: display.uuid)
        // NSWorkspace can report no file or a placeholder, and then the wallpaper store names what is
        // on screen, which may be a render. A render must never be taken for the original.
        let resolved = WallpaperSource.resolve(current: current.url, display: display.uuid, space: key.space, indexPlist: indexPlist).url
        // If macOS still names a deleted render for this Space, keep that path visible to the Off path.
        // A persisted record can still tell us what to restore even though ImageIO cannot decode the file.
        let indexed = indexPlist.flatMap { IndexPlist.imageURL(in: $0, display: display.uuid, space: key.space) }
        let named = current.url ?? indexed
        let missingRender = named.flatMap {
            store.isRender($0) && !FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        let shown = resolved ?? missingRender
        let showingRender = shown.map(store.isRender) ?? false
        let scannedOrigin = shown.flatMap { shown in
            offRenders[key].flatMap { Self.sameFile($0.url, shown) ? $0.origin : nil }
        }
        let origin = showingRender ? scannedOrigin ?? shown.flatMap { self.origin(ofRender: $0, display: display) } : nil
        guard !showingRender || origin != nil else {
            return .failed("This desktop shows a wallpaper OpenNotch painted, but not which wallpaper it painted over. Choose your wallpaper again in System Settings.")
        }

        if !enabled {
            if let origin, let shown {
                let options = current.url.map { Self.sameFile($0, shown) } == true ? current.options : origin.originalOptions
                try system.setWallpaper(origin.originalURL, options: options, display: display.uuid)
            }
            recordOffDesktops(offRenders, display: display.uuid, excluding: key)
            try store.forget([key] + staleKeys)
            return .off
        }

        let original: (url: URL?, options: DesktopOptions)
        if let origin, let shown {
            // Renders are set with the original options, so other options reported with one are the user's new choice.
            original = (origin.originalURL, current.url.map { Self.sameFile($0, shown) } == true ? current.options : origin.originalOptions)
        } else {
            original = current
        }

        let source: URL
        let isDynamic: Bool
        // While a render shows, the wallpaper store names the render, so only the saved original will do.
        switch WallpaperSource.resolve(current: original.url, display: display.uuid, space: key.space, indexPlist: origin == nil ? indexPlist : nil) {
        case .image(let url):
            (source, isDynamic) = (url, false)
        case .dynamic(let url):
            (source, isDynamic) = (url, true)
        case .unsupported:
            guard origin == nil else {
                return .failed("The wallpaper OpenNotch painted over can't be opened. Choose your wallpaper again in System Settings.")
            }
            try store.forget([key])
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
        // A still is uncompressed TIFF. On an M1 Pro, a 4112 x 2658 one encodes in 13 ms and the
        // wallpaper agent decodes it in 14 ms, where a PNG took 540 ms and 150 ms. It is 33 MB on disk,
        // and the folder only keeps renders on show.
        let rendered = store.rendersDirectory.appending(path: "\(renderKey.digest).\(isDynamic ? "heic" : "tiff")")
        if !FileManager.default.fileExists(atPath: rendered.path) {
            try await paint(source, to: rendered, isDynamic: isDynamic, key: renderKey, display: display.uuid)
            // The user can switch Spaces or pick another wallpaper while it draws; start over from what is on screen.
            let now = system.wallpaper(display: display.uuid)
            let spacesNow = system.spaces(display: display.uuid)
            if spacesNow?.current.uuid != key.space || now.url != current.url || now.options != current.options {
                return try await reconcile(display: display, spaces: spacesNow, enabled: enabled, settings: settings, indexPlist: indexPlist, offRenders: offRenders)
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
    private func paint(_ source: URL, to rendered: URL, isDynamic: Bool, key: RenderKey, display: String) async throws {
        painting = RenderProgress()
        defer { painting = nil }
        let reusable = placed[display].flatMap { $0.key == key.placed ? $0 : nil }
        let (updates, continuation) = AsyncStream.makeStream(of: RenderProgress.self)
        let work = Task.detached(priority: .utility) { () throws -> PlacedWallpaper? in
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
                return nil
            }
            let placed = try reusable ?? PlacedWallpaper(
                key: key.placed,
                image: WallpaperRenderer.place(
                    WallpaperRenderer.load(source, for: key.geometry, placement: key.placement),
                    geometry: key.geometry,
                    placement: key.placement,
                    background: key.background
                )
            )
            try WallpaperRenderer.write(
                WallpaperRenderer.finish(placed.image, geometry: key.geometry, corners: key.corners, band: key.band.light),
                to: rendered
            )
            return placed
        }
        for await update in updates { painting = update }
        guard let kept = try await work.value else { return }
        placed[display] = kept
        forgetPlaced?.cancel()
        forgetPlaced = Task { [weak self] in
            try? await Task.sleep(for: Self.placedLifetime)
            guard !Task.isCancelled else { return }
            self?.placed = [:]
        }
    }

    /// What a render was drawn from. A render from before OpenNotch kept that on the file has none, but
    /// its name is a hash of everything that drew it, so a saved original proves itself by hashing to it
    /// under some corner style and band colors the menu offers.
    private func origin(ofRender render: URL, display: DisplaySnapshot) -> RenderOrigin? {
        if let origin = store.origin(ofRender: render) { return origin }
        return Set(store.applied.values.map(\.origin)).first { origin in
            guard !store.isRender(origin.originalURL), let stamp = try? Self.stamp(origin.originalURL) else { return false }
            return CornerStyle.allCases.contains { corners in
                BandColors.palette.contains { candidate in
                    RenderKey(
                        sourcePath: origin.originalURL.path,
                        sourceStamp: stamp,
                        placement: origin.originalOptions.placement,
                        background: origin.originalOptions.background,
                        geometry: display.geometry,
                        corners: corners,
                        band: candidate
                    ).drew(render)
                }
            }
        }
    }

    /// Captures origins for every off desktop before any display forgets records, including the current desktop.
    /// Missing render files are ignored; their absence must not prevent another Space from being restored.
    private func desktopsShowingRenders(display: DisplaySnapshot, spaces: DisplaySpaces?, indexPlist: Data) -> [SpaceKey: DesktopRender] {
        guard let spaces else { return [:] }
        var result: [SpaceKey: DesktopRender] = [:]
        for space in spaces.all where space.isDesktop {
            let key = SpaceKey(display: display.uuid, space: space.uuid)
            let currentURL = space.uuid == spaces.current.uuid ? system.wallpaper(display: display.uuid).url : nil
            guard let shown = currentURL ?? IndexPlist.imageURL(in: indexPlist, display: display.uuid, space: space.uuid),
                  store.isRender(shown),
                  let origin = self.origin(ofRender: shown, display: display)
            else { continue }
            result[key] = DesktopRender(key: key, url: shown, origin: origin)
        }
        return result
    }

    /// Call only after the current Space has been handled. One unrecordable copied render must not block Off.
    private func recordOffDesktops(_ renders: [SpaceKey: DesktopRender], display: String, excluding current: SpaceKey?) {
        for render in renders.values where render.key.display == display && store.applied[render.key] == nil {
            guard current.map({ $0 == render.key }) != true else { continue }
            try? store.record(AppliedWallpaper(key: render.key, originalURL: render.origin.originalURL, originalOptions: render.origin.originalOptions, renderedURL: render.url))
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
