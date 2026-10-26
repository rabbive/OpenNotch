import Foundation

public struct SpaceKey: Hashable, Codable, Sendable {
    public let display: String
    /// Nil when Spaces can't be read; the wallpaper is then keyed by display alone.
    public let space: String?

    public init(display: String, space: String?) {
        self.display = display
        self.space = space
    }
}

/// One Space whose wallpaper OpenNotch replaced, and what to set back.
public struct AppliedWallpaper: Codable, Equatable, Sendable {
    public let key: SpaceKey
    public let originalURL: URL
    public let originalOptions: DesktopOptions
    public let renderedURL: URL

    public init(key: SpaceKey, originalURL: URL, originalOptions: DesktopOptions, renderedURL: URL) {
        self.key = key
        self.originalURL = originalURL
        self.originalOptions = originalOptions
        self.renderedURL = renderedURL
    }
}

/// Every replaced wallpaper, saved as JSON after each change so a revert still works after a relaunch,
/// plus the renders themselves. The render folder holds only files a record points to, so its size
/// is bounded by the Spaces OpenNotch changed, and a returning Space finds its render still there.
@MainActor
public final class Store {
    public let directory: URL
    public private(set) var applied: [SpaceKey: AppliedWallpaper] = [:]

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpenNotch")
    }

    public var rendersDirectory: URL { directory.appending(path: "Renders") }
    private var fileURL: URL { directory.appending(path: "applied.json") }

    /// Throws on a corrupt file rather than starting empty, which would lose every revert.
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: rendersDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let list = try JSONDecoder().decode([AppliedWallpaper].self, from: Data(contentsOf: fileURL))
            applied = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { $1 })
        }
        removeUnreferencedRenders()
    }

    public func isRender(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().path == rendersDirectory.resolvingSymlinksInPath().path
    }

    public func record(_ wallpaper: AppliedWallpaper) throws {
        guard applied[wallpaper.key] != wallpaper else { return }
        applied[wallpaper.key] = wallpaper
        try save()
        removeUnreferencedRenders()
    }

    public func forget(_ keys: some Sequence<SpaceKey>) throws {
        let removed = keys.compactMap { applied.removeValue(forKey: $0) }
        guard !removed.isEmpty else { return }
        try save()
        removeUnreferencedRenders()
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Array(applied.values)).write(to: fileURL, options: .atomic)
    }

    /// Sweeps the whole folder, so renders left by a crash or a failed set, half-written files,
    /// and renders from an older renderer version go too.
    private func removeUnreferencedRenders() {
        let referenced = Set(applied.values.map(\.renderedURL.lastPathComponent))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rendersDirectory.path) else { return }
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: rendersDirectory.appending(path: name))
        }
    }
}
