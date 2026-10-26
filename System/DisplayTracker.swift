import AppKit
import OpenNotchCore

public struct DisplaySnapshot: Equatable, Sendable {
    public let uuid: String
    public let geometry: BarGeometry

    public init(uuid: String, geometry: BarGeometry) {
        self.uuid = uuid
        self.geometry = geometry
    }
}

@MainActor
public enum DisplayTracker {
    public static func builtin() -> (NSScreen, DisplaySnapshot)? {
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen), CGDisplayIsBuiltin(id) != 0, let uuid = uuid(of: id) else { continue }
            let geometry = BarGeometry(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top,
                scale: screen.backingScaleFactor
            )
            return (screen, DisplaySnapshot(uuid: uuid, geometry: geometry))
        }
        return nil
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
