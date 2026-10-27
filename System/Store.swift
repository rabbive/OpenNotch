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

    public var origin: RenderOrigin {
        RenderOrigin(originalURL: originalURL, originalOptions: originalOptions)
    }
}

/// What a render was drawn from, kept on the render file as an extended attribute so it lasts exactly
/// as long as the file. macOS copies a wallpaper OpenNotch sets onto other Spaces, which keep showing it
/// after the Space it was drawn for has moved on, so a Space's record can't be the only way back.
public struct RenderOrigin: Codable, Hashable, Sendable {
    public let originalURL: URL
    public let originalOptions: DesktopOptions

    public init(originalURL: URL, originalOptions: DesktopOptions) {
        self.originalURL = originalURL
        self.originalOptions = originalOptions
    }

    static let attribute = "io.github.rabbive.OpenNotch.origin"

    /// Nil for a file with none, such as a render from before OpenNotch kept them.
    public static func read(from render: URL) -> RenderOrigin? {
        render.withUnsafeFileSystemRepresentation { path -> RenderOrigin? in
            guard let path else { return nil }
            let size = getxattr(path, attribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, size, 0, 0) }
            guard read == size else { return nil }
            return try? JSONDecoder().decode(RenderOrigin.self, from: data)
        }
    }

    public func write(to render: URL) throws {
        let data = try JSONEncoder().encode(self)
        let status = render.withUnsafeFileSystemRepresentation { path in
            data.withUnsafeBytes { setxattr(path, Self.attribute, $0.baseAddress, $0.count, 0, 0) }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// Every replaced wallpaper, saved as JSON after each change so a revert still works after a relaunch,
/// plus the renders themselves. After each sweep the render folder holds only files a record points
/// to or a live desktop Space shows, so a returning Space finds its render still there.
@MainActor
public final class Store {
    public let directory: URL
    public private(set) var applied: [SpaceKey: AppliedWallpaper] = [:]
    /// Wallpapers shown on live desktop Spaces. A render among them is kept without a record, too.
    private let shownWallpapers: @MainActor () -> [URL]?

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpenNotch")
    }

    public var rendersDirectory: URL { directory.appending(path: "Renders") }
    private var fileURL: URL { directory.appending(path: "applied.json") }

    /// Throws on a corrupt file rather than starting empty, which would lose every revert.
    public init(directory: URL, shownWallpapers: @escaping @MainActor () -> [URL]? = { nil }) throws {
        self.directory = directory
        self.shownWallpapers = shownWallpapers
        try FileManager.default.createDirectory(at: rendersDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let list = try JSONDecoder().decode([AppliedWallpaper].self, from: Data(contentsOf: fileURL))
            applied = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { $1 })
        }
        // Renders drawn before OpenNotch kept an origin on each file get theirs from the records.
        for record in applied.values where RenderOrigin.read(from: record.renderedURL) == nil {
            try? record.origin.write(to: record.renderedURL)
        }
        sweep()
    }

    public func isRender(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().path == rendersDirectory.resolvingSymlinksInPath().path
    }

    /// What `url`, one of OpenNotch's renders, was drawn from, whichever Space shows it.
    public func origin(ofRender url: URL) -> RenderOrigin? {
        if let origin = RenderOrigin.read(from: url) { return origin }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return applied.values.first { $0.renderedURL.standardizedFileURL.resolvingSymlinksInPath().path == path }?.origin
    }

    /// Saves the origin on the render too, before the render can be set.
    public func record(_ wallpaper: AppliedWallpaper) throws {
        if RenderOrigin.read(from: wallpaper.renderedURL) == nil { try wallpaper.origin.write(to: wallpaper.renderedURL) }
        guard applied[wallpaper.key] != wallpaper else { return }
        var updated = applied
        updated[wallpaper.key] = wallpaper
        try save(updated)
    }

    public func forget(_ keys: some Sequence<SpaceKey>) throws {
        var updated = applied
        let removed = keys.compactMap { updated.removeValue(forKey: $0) }
        guard !removed.isEmpty else { return }
        try save(updated)
    }

    /// Memory follows the file only once the file is written, so a failed save changes neither and
    /// the next record tries again.
    private func save(_ updated: [SpaceKey: AppliedWallpaper]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Array(updated.values)).write(to: fileURL, options: .atomic)
        applied = updated
    }

    /// Deletes every render no record names and no live desktop Space shows: renders replaced by newer ones,
    /// left by a crash or a failed set, half-written, or from an older renderer version. If the wallpaper
    /// store cannot be read, leaves every render untouched. Run it once
    /// the wallpapers are set, since a render about to be replaced still counts as shown until then.
    public func sweep() {
        guard let shown = shownWallpapers() else { return }
        let referenced = Set(applied.values.map(\.renderedURL.lastPathComponent) + shown.filter { isRender($0) }.map(\.lastPathComponent))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rendersDirectory.path) else { return }
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: rendersDirectory.appending(path: name))
        }
    }
}
