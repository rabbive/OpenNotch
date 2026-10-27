import CoreGraphics

/// How the wallpaper sits on screen: the Fill, Fit, Stretch and Center choices in System Settings.
public enum Placement: String, Codable, Sendable {
    case fill, fit, stretch, center

    public func rect(for image: CGSize, in canvas: CGSize) -> CGRect {
        let scale: CGFloat
        switch self {
        case .stretch: return CGRect(origin: .zero, size: canvas)
        case .center: scale = 1
        case .fill: scale = max(canvas.width / image.width, canvas.height / image.height)
        case .fit: scale = min(canvas.width / image.width, canvas.height / image.height)
        }
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (canvas.width - size.width) / 2,
            y: (canvas.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// An sRGB color.
public struct RGBA: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBA(red: 0, green: 0, blue: 0)

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// The system's light or dark appearance, which the menu bar follows.
public enum Appearance: String, Codable, Sendable {
    case light, dark
}

/// The band's color under a light and under a dark menu bar.
public struct BandColors: Hashable, Codable, Sendable {
    public var light: RGBA
    public var dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    /// The same color whatever the appearance.
    public init(_ color: RGBA) {
        self.init(light: color, dark: color)
    }

    public static let black = BandColors(.black)

    /// Every pair the menu can set. A still's render uses one color twice, which is among them.
    public static let palette: [BandColors] = BandColor.allCases.flatMap { light in
        BandColor.allCases.map { dark in BandColors(light: light.rgba, dark: dark.rgba) }
    }

    public subscript(appearance: Appearance) -> RGBA {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }
}

/// The band colors the menu offers.
public enum BandColor: String, CaseIterable, Sendable {
    case black, graphite, silver, white

    public var rgba: RGBA {
        switch self {
        case .black: .black
        case .graphite: RGBA(red: 0.2, green: 0.2, blue: 0.21)
        case .silver: RGBA(red: 0.82, green: 0.82, blue: 0.84)
        case .white: RGBA(red: 1, green: 1, blue: 1)
        }
    }
}

public enum CornerStyle: String, CaseIterable, Codable, Sendable {
    case off, small, medium, high

    /// In points; the renderer multiplies by the display scale.
    public var radius: Double {
        switch self {
        case .off: 0
        case .small: 6
        case .medium: 10
        case .high: 16
        }
    }
}
