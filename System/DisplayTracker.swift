import AppKit
import OpenNotchCore

public struct DisplaySnapshot: Equatable, Sendable {
    public let uuid: String
    public let name: String
    public let isBuiltin: Bool
    public let geometry: BarGeometry

    public init(uuid: String, name: String, isBuiltin: Bool, geometry: BarGeometry) {
        self.uuid = uuid
        self.name = name
        self.isBuiltin = isBuiltin
        self.geometry = geometry
    }
}

@MainActor
public enum DisplayTracker {
    /// Every connected display, the built-in one first. Each has its own menu bar height and pixel size.
    public static func displays() -> [DisplaySnapshot] {
        let all = NSScreen.screens.compactMap { screen -> DisplaySnapshot? in
            guard let id = displayID(of: screen), let uuid = uuid(of: id) else { return nil }
            let geometry = BarGeometry(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top,
                scale: screen.backingScaleFactor
            )
            return DisplaySnapshot(uuid: uuid, name: screen.localizedName, isBuiltin: CGDisplayIsBuiltin(id) != 0, geometry: geometry)
        }
        return all.filter(\.isBuiltin) + all.filter { !$0.isBuiltin }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
