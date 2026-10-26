import Foundation
import OpenNotchCore

public enum NotchStatus: Equatable, Sendable {
    case off
    case applied
    case noBuiltinDisplay
    case fullScreenSpace
    case dynamicWallpaper
    case unsupportedWallpaper
    case failed(String)
}

/// Brings the built-in display's current Space in line with the settings. Every trigger calls
/// `sync`, and calling it again with nothing changed sets nothing.
@MainActor
public final class NotchEngine {
    private let system: DesktopSystem
    private let store: Store

    public private(set) var status: NotchStatus = .off
    /// Spaces still showing a render while OpenNotch is off. macOS only lets an app set the wallpaper
    /// of the Space on screen, so each one is restored on the user's next visit.
    public private(set) var spacesToVisit: [String] = []

    public init(system: DesktopSystem, store: Store) {
        self.system = system
        self.store = store
    }

    public func sync(enabled: Bool, corners: CornerStyle) {
        let display = system.builtinDisplay()
        let spaces = display.flatMap { system.spaces(display: $0.uuid) }
        do {
            status = try reconcile(display: display, spaces: spaces, enabled: enabled, corners: corners)
        } catch {
            status = .failed(String(describing: error))
        }
        spacesToVisit = enabled ? [] : labelsOfSpacesToVisit(display: display, spaces: spaces)
    }

    private func reconcile(display: DisplaySnapshot?, spaces: DisplaySpaces?, enabled: Bool, corners: CornerStyle) throws -> NotchStatus {
        guard let display else { return .noBuiltinDisplay }
        if let spaces {
            let live = Set(spaces.all.map(\.uuid))
            try store.forget(store.applied.keys.filter { $0.display == display.uuid && $0.space.map { !live.contains($0) } ?? false })
        }
        if spaces?.current.isDesktop == false { return enabled ? .fullScreenSpace : .off }

        let key = SpaceKey(display: display.uuid, space: spaces?.current.uuid)
        let current = system.wallpaper(display: display.uuid)
        let applied = store.applied[key]
        let showingRender = current.url.map(store.isRender) ?? false

        guard enabled else {
            if let applied, showingRender {
                try system.setWallpaper(applied.originalURL, options: applied.originalOptions, display: display.uuid)
            }
            try store.forget([key])
            return .off
        }

        let original: (url: URL?, options: DesktopOptions)
        if showingRender {
            guard let applied else { return .failed("A render is showing but its original wallpaper wasn't saved") }
            original = (applied.originalURL, applied.originalOptions)
        } else {
            original = current
        }

        let source: URL
        switch WallpaperSource.resolve(current: original.url, display: display.uuid, space: key.space, indexPlist: system.indexPlist()) {
        case .image(let url):
            source = url
        case .dynamic:
            if !showingRender { try store.forget([key]) }
            return .dynamicWallpaper
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
            corners: corners
        )
        let rendered = store.rendersDirectory.appending(path: "\(renderKey.digest).png")
        if !FileManager.default.fileExists(atPath: rendered.path) {
            let image = try WallpaperRenderer.render(
                WallpaperRenderer.load(source),
                geometry: display.geometry,
                placement: renderKey.placement,
                background: renderKey.background,
                corners: corners
            )
            try WallpaperRenderer.writePNG(image, to: rendered)
        }
        if current.url?.path != rendered.path {
            try system.setWallpaper(rendered, options: original.options, display: display.uuid)
        }
        try store.record(AppliedWallpaper(key: key, originalURL: source, originalOptions: original.options, renderedURL: rendered))
        return .applied
    }

    private func labelsOfSpacesToVisit(display: DisplaySnapshot?, spaces: DisplaySpaces?) -> [String] {
        guard let display else { return [] }
        let numbers = Dictionary((spaces?.all ?? []).map { ($0.uuid, $0.number) }, uniquingKeysWith: { first, _ in first })
        return store.applied.keys
            .filter { $0.display == display.uuid && $0.space != spaces?.current.uuid }
            .map { key in key.space.flatMap { numbers[$0] ?? nil } }
            .sorted { ($0 ?? .max) < ($1 ?? .max) }
            .map { number in number.map { "Desktop \($0)" } ?? "Built-in display" }
    }

    static func stamp(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(modified)"
    }
}
