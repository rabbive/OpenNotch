import Foundation
import OpenNotchCore

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
        guard status == 0 else {
            let reason = String(cString: strerror(errno))
            throw RenderError(description: "Couldn't note the original wallpaper on \(render.lastPathComponent): \(reason)")
        }
    }
}

/// Every replaced wallpaper, saved as JSON after each change so a revert still works after a relaunch,
/// plus the renders themselves. After each sweep the render folder holds only files a record points
/// to or the wallpaper store names, so any Space macOS shows one on finds it still there.
@MainActor
public final class Store {
    public let directory: URL
    public private(set) var applied: [SpaceKey: AppliedWallpaper] = [:]
    /// The wallpaper store's contents. A render it names anywhere is kept without a record, too.
    private let wallpaperStore: @MainActor () -> Data?

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpenNotch")
    }

    public var rendersDirectory: URL { directory.appending(path: "Renders") }
    private var fileURL: URL { directory.appending(path: "applied.json") }

    /// Throws on a corrupt file rather than starting empty, which would lose every revert.
    public init(directory: URL, wallpaperStore: @escaping @MainActor () -> Data? = { nil }) throws {
        self.directory = directory
        self.wallpaperStore = wallpaperStore
        try FileManager.default.createDirectory(at: rendersDirectory, withIntermediateDirectories: true)
        // A still render is a 33 MB TIFF, and any of them can be drawn again from its original.
        var renders = rendersDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? renders.setResourceValues(values)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let list = try JSONDecoder().decode([AppliedWallpaper].self, from: Data(contentsOf: fileURL))
            applied = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { $1 })
        }
        // Renders drawn before OpenNotch kept an origin on each file get theirs from the records.
        for record in applied.values where !isRender(record.originalURL) && RenderOrigin.read(from: record.renderedURL) == nil {
            try? record.origin.write(to: record.renderedURL)
        }
        sweep()
    }

    public func isRender(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().path == rendersDirectory.resolvingSymlinksInPath().path
    }

    /// What `url`, one of OpenNotch's renders, was drawn from, whichever Space shows it. Never another render.
    public func origin(ofRender url: URL) -> RenderOrigin? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let recorded = applied.values.filter { $0.renderedURL.standardizedFileURL.resolvingSymlinksInPath().path == path }.map(\.origin)
        return ([RenderOrigin.read(from: url)].compactMap { $0 } + recorded).first { !isRender($0.originalURL) }
    }

    /// Saves the origin on the render too, before the render can be set. Refuses a render as the original,
    /// since the sweep deletes renders and turning off would set a file that is gone.
    public func record(_ wallpaper: AppliedWallpaper) throws {
        guard !isRender(wallpaper.originalURL) else {
            throw RenderError(description: "OpenNotch won't save one of its own renders as the wallpaper to restore.")
        }
        if FileManager.default.fileExists(atPath: wallpaper.renderedURL.path) {
            if RenderOrigin.read(from: wallpaper.renderedURL) == nil { try wallpaper.origin.write(to: wallpaper.renderedURL) }
        } else if !isRender(wallpaper.renderedURL) {
            throw RenderError(description: "OpenNotch can't record a missing render file.")
        }
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

    /// Deletes every render no record names and the wallpaper store names nowhere: renders replaced by newer
    /// ones, left by a crash or a failed set, half-written, or from an older renderer version. macOS copies a
    /// wallpaper OpenNotch sets into SystemDefault, which it gives new desktops, and into Spaces of displays
    /// that may come back, so any entry counts. If the wallpaper store cannot be read, leaves every render
    /// untouched. Run it once the wallpapers are set, since a render about to be replaced still counts until then.
    public func sweep() {
        guard let data = wallpaperStore(), let named = IndexPlist.imageURLs(in: data) else { return }
        let referenced = Set(applied.values.map(\.renderedURL.lastPathComponent) + named.filter { isRender($0) }.map(\.lastPathComponent))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rendersDirectory.path) else { return }
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: rendersDirectory.appending(path: name))
        }
    }
}
