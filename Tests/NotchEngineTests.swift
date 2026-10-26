import AppKit
import OpenNotchCore
import OpenNotchSystem
import Testing

@MainActor
final class FakeDesktop: DesktopSystem {
    var display: DisplaySnapshot? = DisplaySnapshot(
        uuid: "BUILTIN",
        geometry: BarGeometry(pixelWidth: 64, pixelHeight: 40, bandHeight: 6, scale: 2)
    )
    var spaceIDs = ["", "S2", "S3"]
    var fullScreen: Set<String> = []
    var currentSpace = ""
    var wallpapers: [String: (url: URL?, options: DesktopOptions)] = [:]
    private(set) var setCount = 0

    func builtinDisplay() -> DisplaySnapshot? { display }

    func spaces(display: String) -> DisplaySpaces? {
        var desktops = 0
        let all = spaceIDs.map { id in
            let isDesktop = !fullScreen.contains(id)
            if isDesktop { desktops += 1 }
            return SpaceInfo(uuid: id, isDesktop: isDesktop, number: isDesktop ? desktops : nil)
        }
        return DisplaySpaces(current: all.first { $0.uuid == currentSpace }!, all: all)
    }

    func wallpaper(display: String) -> (url: URL?, options: DesktopOptions) {
        wallpapers[currentSpace] ?? (nil, DesktopOptions())
    }

    func setWallpaper(_ url: URL, options: DesktopOptions, display: String) throws {
        wallpapers[currentSpace] = (url, options)
        setCount += 1
    }

    func indexPlist() -> Data? { nil }
}

@MainActor
struct NotchEngineTests {
    let folder: URL
    let photo: URL
    let otherPhoto: URL
    let options = DesktopOptions(scaling: 3, allowClipping: true, fillColor: NSColor(calibratedRed: 0.25, green: 0.41, blue: 0.67, alpha: 1))
    let desktop = FakeDesktop()

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "OpenNotchEngine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        photo = folder.appending(path: "photo.png")
        otherPhoto = folder.appending(path: "other.png")
        try WallpaperRenderer.writePNG(TestImages.quadrants(), to: photo)
        try WallpaperRenderer.writePNG(TestImages.quadrants(width: 30, height: 30), to: otherPhoto)
        for space in desktop.spaceIDs { desktop.wallpapers[space] = (photo, options) }
    }

    func makeEngine() throws -> (NotchEngine, Store) {
        let store = try Store(directory: folder.appending(path: "State"))
        return (NotchEngine(system: desktop, store: store), store)
    }

    func renders() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "State/Renders").path)
    }

    func visit(_ space: String, _ engine: NotchEngine, enabled: Bool) {
        desktop.currentSpace = space
        engine.sync(enabled: enabled, corners: .off)
    }

    @Test func turningOnShowsABandedRenderWithTheOriginalOptions() throws {
        let (engine, store) = try makeEngine()
        engine.sync(enabled: true, corners: .off)
        #expect(engine.status == .applied)
        let shown = try #require(desktop.wallpapers[""]?.url)
        #expect(store.isRender(shown))
        #expect(desktop.wallpapers[""]?.options == options)
        let pixels = TestImages.Pixels(try WallpaperRenderer.load(shown))
        #expect(pixels.width == 64 && pixels.height == 40)
        #expect(pixels[0, 0] == [0, 0, 0] && pixels[63, 5] == [0, 0, 0])
        #expect(pixels[10, 6] != [0, 0, 0])
    }

    @Test func syncingAgainSetsNothing() throws {
        let (engine, _) = try makeEngine()
        engine.sync(enabled: true, corners: .off)
        engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 1)
    }

    @Test func turningOffRestoresTheSpaceOnScreenAndListsTheRest() throws {
        let (engine, _) = try makeEngine()
        for space in ["", "S2", "S3", ""] { visit(space, engine, enabled: true) }
        engine.sync(enabled: false, corners: .off)
        #expect(desktop.wallpapers[""]?.url == photo)
        #expect(desktop.wallpapers[""]?.options == options)
        #expect(engine.spacesToVisit == ["Desktop 2", "Desktop 3"])
    }

    @Test func visitingEachSpaceWhileOffRestoresItAndCleansUp() throws {
        let (engine, _) = try makeEngine()
        for space in ["", "S2", "S3", ""] { visit(space, engine, enabled: true) }
        engine.sync(enabled: false, corners: .off)
        visit("S2", engine, enabled: false)
        #expect(desktop.wallpapers["S2"]?.url == photo)
        #expect(engine.spacesToVisit == ["Desktop 3"])
        visit("S3", engine, enabled: false)
        #expect(desktop.wallpapers["S3"]?.url == photo)
        #expect(engine.spacesToVisit.isEmpty)
        #expect(try renders().isEmpty)
    }

    @Test func revertWorksAfterARelaunch() throws {
        try makeEngine().0.sync(enabled: true, corners: .off)
        let (relaunched, _) = try makeEngine()
        relaunched.sync(enabled: false, corners: .off)
        #expect(desktop.wallpapers[""]?.url == photo)
        #expect(desktop.wallpapers[""]?.options == options)
    }

    @Test func aNewWallpaperBecomesTheOneToRestore() throws {
        let (engine, _) = try makeEngine()
        engine.sync(enabled: true, corners: .off)
        desktop.wallpapers[""] = (otherPhoto, options)
        engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 2)
        #expect(try renders().count == 1)
        engine.sync(enabled: false, corners: .off)
        #expect(desktop.wallpapers[""]?.url == otherPhoto)
    }

    @Test func aWallpaperChangedWhileAwayIsKept() throws {
        let (engine, _) = try makeEngine()
        for space in ["S2", ""] { visit(space, engine, enabled: true) }
        engine.sync(enabled: false, corners: .off)
        desktop.wallpapers["S2"] = (otherPhoto, options)
        let sets = desktop.setCount
        visit("S2", engine, enabled: false)
        #expect(desktop.wallpapers["S2"]?.url == otherPhoto)
        #expect(desktop.setCount == sets)
        #expect(engine.spacesToVisit.isEmpty)
    }

    @Test func changingCornersReplacesTheRender() throws {
        let (engine, _) = try makeEngine()
        engine.sync(enabled: true, corners: .off)
        engine.sync(enabled: true, corners: .high)
        #expect(desktop.setCount == 2)
        #expect(try renders().count == 1)
    }

    @Test func fullScreenSpacesAreLeftAlone() throws {
        let (engine, _) = try makeEngine()
        desktop.fullScreen = ["S2"]
        visit("S2", engine, enabled: true)
        #expect(engine.status == .fullScreenSpace)
        #expect(desktop.setCount == 0)
    }

    @Test func unsupportedWallpapersAreLeftAlone() throws {
        let (engine, _) = try makeEngine()
        desktop.wallpapers[""] = (folder, options)
        engine.sync(enabled: true, corners: .off)
        #expect(engine.status == .unsupportedWallpaper)
        #expect(desktop.setCount == 0)
    }

    @Test func removedSpacesDropOffTheList() throws {
        let (engine, _) = try makeEngine()
        for space in ["S2", ""] { visit(space, engine, enabled: true) }
        engine.sync(enabled: false, corners: .off)
        #expect(engine.spacesToVisit == ["Desktop 2"])
        desktop.spaceIDs = [""]
        engine.sync(enabled: false, corners: .off)
        #expect(engine.spacesToVisit.isEmpty)
    }

    @Test func noBuiltinDisplayMeansNothingToDo() throws {
        let (engine, _) = try makeEngine()
        desktop.display = nil
        engine.sync(enabled: true, corners: .off)
        #expect(engine.status == .noBuiltinDisplay)
        #expect(desktop.setCount == 0)
    }
}
