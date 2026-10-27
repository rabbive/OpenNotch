import AppKit
import OpenNotchCore

/// NSWorkspace desktop image options in Codable form, so a revert after relaunch sets back
/// exactly what was there. Missing keys stay missing.
public struct DesktopOptions: Codable, Hashable, Sendable {
    public var scaling: UInt?
    public var allowClipping: Bool?
    /// The original NSColor, keyed-archived to keep its color space.
    public var fillColor: Data?

    public init(scaling: UInt? = nil, allowClipping: Bool? = nil, fillColor: NSColor? = nil) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    }

    public init(_ options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        self.init(
            scaling: (options[.imageScaling] as? NSNumber)?.uintValue,
            allowClipping: (options[.allowClipping] as? NSNumber)?.boolValue,
            fillColor: options[.fillColor] as? NSColor
        )
    }

    public var dictionary: [NSWorkspace.DesktopImageOptionKey: Any] {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling { options[.imageScaling] = NSNumber(value: scaling) }
        if let allowClipping { options[.allowClipping] = NSNumber(value: allowClipping) }
        if let color { options[.fillColor] = color }
        return options
    }

    public var color: NSColor? {
        fillColor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }
    }

    public var placement: Placement {
        switch scaling.flatMap(NSImageScaling.init(rawValue:)) {
        case .scaleAxesIndependently: .stretch
        case .scaleNone: .center
        default: allowClipping ?? true ? .fill : .fit
        }
    }

    public var background: RGBA {
        guard let color = color?.usingColorSpace(.sRGB) else { return .black }
        return RGBA(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent)
        )
    }
}
