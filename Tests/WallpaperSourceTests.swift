import CoreGraphics
import Foundation
import ImageIO
import OpenNotchCore
import OpenNotchSystem
import Testing
import UniformTypeIdentifiers

struct WallpaperSourceTests {
    let folder: URL
    let still: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "OpenNotchSource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        still = folder.appending(path: "still.png")
        try WallpaperRenderer.writePNG(TestImages.quadrants(), to: still)
    }

    static func plist(_ value: Any) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    static func desktop(_ url: URL, provider: String = "com.apple.wallpaper.choice.image") -> [String: Any] {
        let configuration = plist(["type": "imageFile", "url": ["relative": url.absoluteString]])
        return ["Desktop": ["Content": ["Choices": [["Provider": provider, "Configuration": configuration, "Files": [Any]()]]]]]
    }

    @Test func anImageFileIsUsedDirectly() {
        #expect(WallpaperSource.resolve(current: still, display: "D", space: nil, indexPlist: nil) == .image(still))
    }

    @Test func aMultiImageFileIsDynamic() throws {
        let heicLike = folder.appending(path: "dynamic.tiff")
        let destination = try #require(CGImageDestinationCreateWithURL(heicLike as CFURL, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, TestImages.quadrants(), nil)
        CGImageDestinationAddImage(destination, TestImages.quadrants(), nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(WallpaperSource.resolve(current: heicLike, display: "D", space: nil, indexPlist: nil) == .dynamic(heicLike))
    }

    @Test func aNonImageFallsBackToTheWallpaperStore() {
        let index = Self.plist(["Displays": ["D": Self.desktop(still)]])
        #expect(WallpaperSource.resolve(current: folder, display: "D", space: nil, indexPlist: index) == .image(still))
    }

    @Test func nothingUsableIsUnsupported() {
        let aerial = Self.plist(["Displays": ["D": Self.desktop(still, provider: "com.apple.wallpaper.choice.aerials")]])
        #expect(WallpaperSource.resolve(current: folder, display: "D", space: nil, indexPlist: aerial) == .unsupported)
        #expect(WallpaperSource.resolve(current: nil, display: "D", space: nil, indexPlist: nil) == .unsupported)
    }
}

struct IndexPlistTests {
    let display = URL(fileURLWithPath: "/w/display.jpg")
    let space = URL(fileURLWithPath: "/w/space.jpg")
    let spaceDefault = URL(fileURLWithPath: "/w/space default.jpg")
    let everywhere = URL(fileURLWithPath: "/w/everywhere.jpg")

    var store: Data {
        WallpaperSourceTests.plist([
            "AllSpacesAndDisplays": WallpaperSourceTests.desktop(everywhere),
            "Displays": ["D": WallpaperSourceTests.desktop(display)],
            "Spaces": [
                "S1": ["Displays": ["D": WallpaperSourceTests.desktop(space)]],
                "": ["Default": WallpaperSourceTests.desktop(spaceDefault)],
            ],
        ])
    }

    @Test func theMostSpecificEntryWins() {
        #expect(IndexPlist.imageURL(in: store, display: "D", space: "S1") == space)
        #expect(IndexPlist.imageURL(in: store, display: "D", space: "") == spaceDefault)
        #expect(IndexPlist.imageURL(in: store, display: "D", space: "unknown") == display)
        #expect(IndexPlist.imageURL(in: store, display: "other", space: nil) == everywhere)
    }

    @Test func unrecognisedDataYieldsNothing() {
        #expect(IndexPlist.imageURL(in: Data("not a plist".utf8), display: "D", space: nil) == nil)
        #expect(IndexPlist.imageURL(in: WallpaperSourceTests.plist(["Displays": ["D": ["Desktop": "?"]]]), display: "D", space: nil) == nil)
    }
}
