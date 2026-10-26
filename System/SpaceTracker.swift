import Foundation

public struct SpaceInfo: Hashable, Sendable {
    /// Empty for the first desktop Space, which macOS creates without a UUID.
    public let uuid: String
    /// False for full-screen app Spaces, which show no wallpaper.
    public let isDesktop: Bool
    /// The N in "Desktop N", as Mission Control numbers desktop Spaces.
    public let number: Int?

    public init(uuid: String, isDesktop: Bool, number: Int?) {
        self.uuid = uuid
        self.isDesktop = isDesktop
        self.number = number
    }
}

public struct DisplaySpaces: Sendable {
    public let current: SpaceInfo
    public let all: [SpaceInfo]

    public init(current: SpaceInfo, all: [SpaceInfo]) {
        self.current = current
        self.all = all
    }
}

/// Reads Mission Control's Spaces from SkyLight. These calls are private, so they are looked up at
/// runtime and every caller copes with nil by keying wallpapers by display alone.
public enum SpaceTracker {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let symbols: (MainConnection, CopyManagedDisplaySpaces)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(copy, to: CopyManagedDisplaySpaces.self))
    }()

    public static func spaces(display: String) -> DisplaySpaces? {
        guard let (main, copy) = symbols,
              let list = copy(main())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let entry = list.first { $0["Display Identifier"] as? String == display } ?? (list.count == 1 ? list.first : nil)
        return entry.flatMap(parse)
    }

    static func parse(_ entry: [String: Any]) -> DisplaySpaces? {
        guard let currentUUID = (entry["Current Space"] as? [String: Any])?["uuid"] as? String,
              let spaces = entry["Spaces"] as? [[String: Any]]
        else { return nil }
        var desktops = 0
        let all = spaces.compactMap { space -> SpaceInfo? in
            guard let uuid = space["uuid"] as? String else { return nil }
            let isDesktop = space["type"] as? Int == 0
            if isDesktop { desktops += 1 }
            return SpaceInfo(uuid: uuid, isDesktop: isDesktop, number: isDesktop ? desktops : nil)
        }
        guard let current = all.first(where: { $0.uuid == currentUUID }) else { return nil }
        return DisplaySpaces(current: current, all: all)
    }
}
