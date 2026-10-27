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
    /// One color twice, unless the frames switch with the appearance; see `DynamicHEIC.render`.
    public var band: BandColors

    public init(
        sourcePath: String,
        sourceStamp: String,
        placement: Placement,
        background: RGBA,
        geometry: BarGeometry,
        corners: CornerStyle,
        band: BandColors
    ) {
        self.sourcePath = sourcePath
        self.sourceStamp = sourceStamp
        self.placement = placement
        self.background = background
        self.geometry = geometry
        self.corners = corners
        self.band = band
    }

    /// Bump when the renderer's output changes for the same inputs.
    static let rendererVersion = 2

    public var digest: String {
        "v\(Self.rendererVersion)-\(fingerprint)"
    }

    /// The digest without the renderer version, so it also names what older versions drew from these inputs.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data(String(describing: self).utf8)
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `render` was drawn from these inputs, by this renderer or an older one. A render's name
    /// is a hash of its inputs, so a match proves where it came from.
    public func drew(_ render: URL) -> Bool {
        render.deletingPathExtension().lastPathComponent.hasSuffix("-\(fingerprint)")
    }

    /// These inputs without the band and corners: what `WallpaperRenderer.place` draws from.
    public var placed: RenderKey {
        var key = self
        key.corners = .off
        key.band = .black
        return key
    }
}
