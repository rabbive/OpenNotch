import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderError: Error, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

public enum WallpaperRenderer {
    /// Draws `source` the way macOS would place it on a `geometry`-sized screen, then paints the
    /// band (and rounded corners) in `band`. The result matches the screen pixel for pixel, so the
    /// system shows it unscaled whatever placement option it is set with.
    public static func render(
        _ source: CGImage,
        geometry: BarGeometry,
        placement: Placement,
        background: RGBA,
        corners: CornerStyle,
        band: RGBA
    ) throws -> CGImage {
        let space = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: geometry.pixelWidth,
            height: geometry.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw RenderError(description: "Can't create a \(geometry.pixelWidth)x\(geometry.pixelHeight) canvas") }
        let canvas = CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight)
        context.setFillColor(background.cgColor)
        context.fill(canvas)
        context.interpolationQuality = .high
        context.draw(source, in: placement.rect(for: CGSize(width: source.width, height: source.height), in: canvas.size))
        context.setFillColor(band.cgColor)
        context.addPath(maskPath(geometry: geometry, corners: corners))
        context.fillPath(using: .evenOdd)
        guard let image = context.makeImage() else { throw RenderError(description: "Can't finish the render") }
        return image
    }

    /// The canvas minus a rounded rect that starts under the band and runs off the bottom edge,
    /// so even-odd filling paints the band and only the two top corners.
    public static func maskPath(geometry: BarGeometry, corners: CornerStyle) -> CGPath {
        let width = CGFloat(geometry.pixelWidth)
        let height = CGFloat(geometry.pixelHeight)
        let below = height - CGFloat(geometry.bandHeight)
        let radius = max(0, min(CGFloat(corners.radius * geometry.scale), width / 2, below / 2))
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        path.addRoundedRect(
            in: CGRect(x: 0, y: -radius, width: width, height: below + radius),
            cornerWidth: radius,
            cornerHeight: radius
        )
        return path
    }

    public static func load(_ url: URL, for geometry: BarGeometry, placement: Placement) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { throw RenderError(description: "Can't read \(url.lastPathComponent)") }
        return try load(source, at: CGImageSourceGetPrimaryImageIndex(source), for: geometry, placement: placement)
    }

    /// Decodes no more pixels than the frame covers once placed on a `geometry`-sized screen, so a 6K
    /// photo costs about what the screen does and `render` draws it at about 1:1. Center shows the
    /// source pixel for pixel, and a frame smaller than the screen has nothing to spare, so those decode in full.
    public static func load(_ source: CGImageSource, at index: Int, for geometry: BarGeometry, placement: Placement) throws -> CGImage {
        let full = { () throws -> CGImage in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil)
            else { throw RenderError(description: "Can't read frame \(index)") }
            return image
        }
        guard placement != .center,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return try full() }
        let size = CGSize(width: width, height: height)
        let placed = placement.rect(for: size, in: CGSize(width: geometry.pixelWidth, height: geometry.pixelHeight))
        let scale = max(placed.width / size.width, placed.height / size.height)
        // Rounding error alone must not ask for one pixel more than the screen shows.
        let longestSide = Int((max(size.width, size.height) * scale - 0.001).rounded(.up))
        guard longestSide < max(width, height) else { return try full() }
        // Without the transform option the thumbnail keeps the orientation a full decode has, so both place alike.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        else { throw RenderError(description: "Can't read frame \(index)") }
        return image
    }

    /// Writes beside the destination and renames, so a crash never leaves a half-written wallpaper.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        let partial = url.appendingPathExtension("partial")
        guard let destination = CGImageDestinationCreateWithURL(partial as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError(description: "Can't write \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError(description: "Can't encode \(url.lastPathComponent)") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
    }
}
