import Foundation
import ImageIO
import OpenNotchCore

public enum WallpaperChoice: Equatable, Sendable {
    case image(URL)
    /// A multi-image HEIC whose apple_desktop tags change it with time of day or appearance.
    case dynamic(URL)
    /// Aerials, Photos shuffles, Apple collections: no single image file to paint on.
    case unsupported

    public var url: URL? {
        switch self {
        case .image(let url), .dynamic(let url): url
        case .unsupported: nil
        }
    }
}

public enum WallpaperSource {
    /// Trusts what NSWorkspace reports when it is an image file, and only then falls back to
    /// the wallpaper store's record for this display and Space.
    public static func resolve(current: URL?, display: String, space: String?, indexPlist: Data?) -> WallpaperChoice {
        if let current, let choice = classify(current) { return choice }
        if let indexPlist,
           let url = IndexPlist.imageURL(in: indexPlist, display: display, space: space),
           let choice = classify(url) {
            return choice
        }
        return .unsupported
    }

    static func classify(_ url: URL) -> WallpaperChoice? {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) != nil
        else { return nil }
        switch CGImageSourceGetCount(source) {
        case 0: return nil
        case 1: return .image(url)
        default: return DynamicHEIC.hasSchedule(source) ? .dynamic(url) : .image(url)
        }
    }
}

/// The wallpaper store macOS keeps at ~/Library/Application Support/com.apple.wallpaper/Store.
/// It is private and undocumented, so any shape this code does not recognise yields nil.
public enum IndexPlist {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    public static func imageURL(in data: Data, display: String, space: String?) -> URL? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let spaceEntry = space.flatMap { (root["Spaces"] as? [String: Any])?[$0] as? [String: Any] }
        let mostSpecificFirst: [Any?] = [
            (spaceEntry?["Displays"] as? [String: Any])?[display],
            spaceEntry?["Default"],
            (root["Displays"] as? [String: Any])?[display],
            root["AllSpacesAndDisplays"],
        ]
        guard let desktop = mostSpecificFirst.lazy.compactMap({ ($0 as? [String: Any])?["Desktop"] as? [String: Any] }).first
        else { return nil }
        return imageURL(of: desktop)
    }

    /// Every image file named anywhere in the store: SystemDefault, which macOS gives new desktops, every
    /// display and every Space, connected or not. Nil when the data is no property list.
    public static func imageURLs(in data: Data) -> [URL]? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        func named(_ value: Any) -> [URL] {
            if let list = value as? [Any] { return list.flatMap(named) }
            guard let entry = value as? [String: Any] else { return [] }
            let own = (entry["Desktop"] as? [String: Any]).flatMap(imageURL(of:))
            return (own.map { [$0] } ?? []) + entry.values.flatMap(named)
        }
        return named(root)
    }

    private static func imageURL(of desktop: [String: Any]) -> URL? {
        guard let choice = ((desktop["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first,
              choice["Provider"] as? String == "com.apple.wallpaper.choice.image",
              let blob = choice["Configuration"] as? Data,
              let configuration = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
              configuration["type"] as? String == "imageFile",
              let relative = (configuration["url"] as? [String: Any])?["relative"] as? String,
              let url = URL(string: relative), url.isFileURL
        else { return nil }
        return url
    }
}
