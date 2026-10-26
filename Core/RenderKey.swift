import CryptoKit
import Foundation

/// Everything that changes the rendered pixels. Its digest names the rendered file, so an unchanged
/// wallpaper maps to the same file, which gets set again instead of rendered again.
public struct RenderKey: Hashable, Codable, Sendable {
    public var sourcePath: String
    /// File size and modification time, so editing the image in place re-renders it.
    public var sourceStamp: String
    public var placement: Placement
    public var background: RGBA
    public var geometry: BarGeometry
    public var corners: CornerStyle

    public init(sourcePath: String, sourceStamp: String, placement: Placement, background: RGBA, geometry: BarGeometry, corners: CornerStyle) {
        self.sourcePath = sourcePath
        self.sourceStamp = sourceStamp
        self.placement = placement
        self.background = background
        self.geometry = geometry
        self.corners = corners
    }

    /// Bump when the renderer's output changes for the same inputs.
    static let rendererVersion = 1

    public var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data(String(describing: self).utf8)
        let hash = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "v\(Self.rendererVersion)-\(hash)"
    }
}
