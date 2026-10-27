import CoreGraphics

/// One display's wallpaper canvas in backing pixels, and the black band painted across its top.
public struct BarGeometry: Hashable, Codable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let bandHeight: Int
    public let scale: Double

    public init(pixelWidth: Int, pixelHeight: Int, bandHeight: Int, scale: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bandHeight = bandHeight
        self.scale = scale
    }

    /// Takes the screen's AppKit rects in points. The safe-area inset keeps the band under the
    /// camera housing when the menu bar hides automatically and `visibleFrame` reaches the top.
    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, scale: CGFloat) {
        let bandPoints = max(frame.maxY - visibleFrame.maxY, safeAreaTop, 0)
        self.init(
            pixelWidth: Int((frame.width * scale).rounded()),
            pixelHeight: Int((frame.height * scale).rounded()),
            bandHeight: Int((bandPoints * scale).rounded(.up)),
            scale: Double(scale)
        )
    }
}
