import AppKit
import ImageIO
import Observation
import OpenNotchCore
import OpenNotchSystem
import Testing

enum Displays {
    static let builtin = DisplaySnapshot(
        uuid: "BUILTIN",
        name: "Built-in Display",
        isBuiltin: true,
        geometry: BarGeometry(pixelWidth: 64, pixelHeight: 40, bandHeight: 6, scale: 2)
    )
    static let external = DisplaySnapshot(
        uuid: "EXTERNAL",
        name: "Studio Display",
        isBuiltin: false,
        geometry: BarGeometry(pixelWidth: 48, pixelHeight: 30, bandHeight: 3, scale: 1)
    )
}

/// Every display shares the same Spaces and current Space; wallpapers are per display and Space.
@MainActor
final class FakeDesktop: DesktopSystem {
    var connected = [Displays.builtin]
    var spaceIDs = ["", "S2", "S3"]
    var fullScreen: Set<String> = []
    var currentSpace = ""
    var failsToSet = false
    /// Like NSWorkspace with an Apple wallpaper: no file reported, so only the wallpaper store says what is shown.
    var reportsNoFile = false
    private var wallpapers: [SpaceKey: (url: URL?, options: DesktopOptions)] = [:]
    private(set) var setCount = 0

    subscript(space: String, on display: String = "BUILTIN") -> (url: URL?, options: DesktopOptions)? {
        get { wallpapers[SpaceKey(display: display, space: space)] }
        set { wallpapers[SpaceKey(display: display, space: space)] = newValue }
    }

    func displays() -> [DisplaySnapshot] { connected }

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
        let wallpaper = self[currentSpace, on: display] ?? (nil, DesktopOptions())
        return reportsNoFile ? (nil, wallpaper.options) : wallpaper
    }

    func setWallpaper(_ url: URL, options: DesktopOptions, display: String) throws {
        if failsToSet { throw RenderError(description: "Set refused") }
        self[currentSpace, on: display] = (url, options)
        setCount += 1
    }

    func indexPlist() -> Data? {
        var spaces: [String: [String: [String: Any]]] = [:]
        for (key, wallpaper) in wallpapers {
            guard let space = key.space, let url = wallpaper.url else { continue }
            spaces[space, default: ["Displays": [:]]]["Displays"]![key.display] = WallpaperSourceTests.desktop(url)
        }
        return WallpaperSourceTests.plist(["Spaces": spaces])
    }
}

/// A sync started from an observation callback, kept so the test can wait for it.
@MainActor
final class StartedSync {
    var task: Task<Void, Never>?
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
        for display in [Displays.builtin, Displays.external] {
            for space in desktop.spaceIDs { desktop[space, on: display.uuid] = (photo, options) }
        }
    }

    func makeEngine() throws -> (NotchEngine, Store) {
        let desktop = self.desktop
        let store = try Store(directory: folder.appending(path: "State")) { IndexPlist.imageURLs(in: desktop.indexPlist() ?? Data()) }
        return (NotchEngine(system: desktop, store: store), store)
    }

    func renders() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "State/Renders").path)
    }

    func visit(_ space: String, _ engine: NotchEngine, enabled: Bool, builtinOnly: Bool = true) async {
        desktop.currentSpace = space
        await engine.sync(enabled: enabled, builtinOnly: builtinOnly, corners: .off)
    }

    func statuses(_ status: NotchStatus, _ displays: DisplaySnapshot...) -> [DisplayStatus] {
        displays.map { DisplayStatus(name: $0.name, status: status) }
    }

    /// Runs `action` once, the moment a render starts drawing, while it still runs.
    func whenPaintingStarts(_ engine: NotchEngine, _ action: @escaping @MainActor @Sendable () -> Void) {
        withObservationTracking { _ = engine.painting } onChange: { MainActor.assumeIsolated(action) }
    }

    @Test func turningOnShowsABandedRenderWithTheOriginalOptions() async throws {
        let (engine, store) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses == statuses(.applied, Displays.builtin))
        let shown = try #require(desktop[""]?.url)
        #expect(store.isRender(shown))
        #expect(desktop[""]?.options == options)
        let pixels = TestImages.Pixels(try WallpaperRenderer.load(shown))
        #expect(pixels.width == 64 && pixels.height == 40)
        #expect(pixels[0, 0] == [0, 0, 0] && pixels[63, 5] == [0, 0, 0])
        #expect(pixels[10, 6] != [0, 0, 0])
    }

    @Test func syncingAgainSetsNothing() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        await engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 1)
    }

    @Test func turningOffRestoresTheSpaceOnScreenAndListsTheRest() async throws {
        let (engine, _) = try makeEngine()
        for space in ["", "S2", "S3", ""] { await visit(space, engine, enabled: true) }
        await engine.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == options)
        #expect(engine.spacesToVisit == ["Desktop 2", "Desktop 3"])
    }

    @Test func visitingEachSpaceWhileOffRestoresItAndCleansUp() async throws {
        let (engine, _) = try makeEngine()
        for space in ["", "S2", "S3", ""] { await visit(space, engine, enabled: true) }
        await engine.sync(enabled: false, corners: .off)
        await visit("S2", engine, enabled: false)
        #expect(desktop["S2"]?.url == photo)
        #expect(engine.spacesToVisit == ["Desktop 3"])
        await visit("S3", engine, enabled: false)
        #expect(desktop["S3"]?.url == photo)
        #expect(engine.spacesToVisit.isEmpty)
        #expect(try renders().isEmpty)
    }

    @Test func revertWorksAfterARelaunch() async throws {
        try await makeEngine().0.sync(enabled: true, corners: .off)
        let (relaunched, _) = try makeEngine()
        await relaunched.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == options)
    }

    @Test func aNewWallpaperBecomesTheOneToRestore() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        desktop[""] = (otherPhoto, options)
        await engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 2)
        #expect(try renders().count == 1)
        await engine.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == otherPhoto)
    }

    @Test func aWallpaperChangedWhileAwayIsKept() async throws {
        let (engine, _) = try makeEngine()
        for space in ["S2", ""] { await visit(space, engine, enabled: true) }
        await engine.sync(enabled: false, corners: .off)
        desktop["S2"] = (otherPhoto, options)
        let sets = desktop.setCount
        await visit("S2", engine, enabled: false)
        #expect(desktop["S2"]?.url == otherPhoto)
        #expect(desktop.setCount == sets)
        #expect(engine.spacesToVisit.isEmpty)
    }

    @Test func changingCornersReplacesTheRender() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        await engine.sync(enabled: true, corners: .high)
        #expect(desktop.setCount == 2)
        #expect(try renders().count == 1)
    }

    @Test func fullScreenSpacesAreLeftAlone() async throws {
        let (engine, _) = try makeEngine()
        desktop.fullScreen = ["S2"]
        await visit("S2", engine, enabled: true)
        #expect(engine.statuses == statuses(.fullScreenSpace, Displays.builtin))
        #expect(desktop.setCount == 0)
    }

    @Test func unsupportedWallpapersAreLeftAlone() async throws {
        let (engine, _) = try makeEngine()
        desktop[""] = (folder, options)
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses == statuses(.unsupportedWallpaper, Displays.builtin))
        #expect(desktop.setCount == 0)
    }

    @Test(.enabled(if: DynamicFixture.canEncode, "This runner can't encode HEIC, so there is no dynamic wallpaper to test with"))
    func dynamicWallpapersKeepEveryFrameAndTheirSchedule() async throws {
        let dynamic = folder.appending(path: "dynamic.heic")
        try #require(DynamicFixture.heic(DynamicFixture.colors.map { DynamicFixture.solid($0) }, tags: DynamicFixture.tags)).write(to: dynamic)
        desktop[""] = (dynamic, options)
        let (engine, store) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses == statuses(.applied, Displays.builtin))
        let shown = try #require(desktop[""]?.url)
        #expect(store.isRender(shown))
        let frames = try #require(CGImageSourceCreateWithURL(shown as CFURL, nil))
        #expect(CGImageSourceGetCount(frames) == DynamicFixture.colors.count)
        #expect(DynamicFixture.appleDesktopTags(of: frames, at: 0) == DynamicFixture.tags)
        await engine.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == dynamic)
        #expect(desktop[""]?.options == options)
        #expect(try renders().isEmpty)
    }

    @Test func removedSpacesDropOffTheList() async throws {
        let (engine, _) = try makeEngine()
        for space in ["S2", ""] { await visit(space, engine, enabled: true) }
        await engine.sync(enabled: false, corners: .off)
        #expect(engine.spacesToVisit == ["Desktop 2"])
        desktop.spaceIDs = [""]
        await engine.sync(enabled: false, corners: .off)
        #expect(engine.spacesToVisit.isEmpty)
    }

    @Test func noBuiltinDisplayMeansNothingToDo() async throws {
        let (engine, _) = try makeEngine()
        desktop.connected = [Displays.external]
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses.isEmpty)
        #expect(desktop.setCount == 0)
    }

    @Test func macBookScreenOnlyLeavesExternalDisplaysAlone() async throws {
        let (engine, _) = try makeEngine()
        desktop.connected = [Displays.builtin, Displays.external]
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses == statuses(.applied, Displays.builtin))
        #expect(desktop["", on: "EXTERNAL"]?.url == photo)
        #expect(desktop.setCount == 1)
    }

    @Test func everyDisplayGetsABandOfItsOwnSize() async throws {
        let (engine, store) = try makeEngine()
        desktop.connected = [Displays.builtin, Displays.external]
        await engine.sync(enabled: true, builtinOnly: false, corners: .off)
        #expect(engine.statuses == statuses(.applied, Displays.builtin, Displays.external))

        let builtin = TestImages.Pixels(try WallpaperRenderer.load(try #require(desktop[""]?.url)))
        #expect(builtin.width == 64 && builtin.height == 40)
        #expect(builtin[0, 5] == [0, 0, 0] && builtin[10, 6] != [0, 0, 0])

        let shown = try #require(desktop["", on: "EXTERNAL"]?.url)
        #expect(store.isRender(shown))
        #expect(desktop["", on: "EXTERNAL"]?.options == options)
        let external = TestImages.Pixels(try WallpaperRenderer.load(shown))
        #expect(external.width == 48 && external.height == 30)
        #expect(external[0, 2] == [0, 0, 0] && external[10, 3] != [0, 0, 0])

        await engine.sync(enabled: true, builtinOnly: false, corners: .off)
        #expect(desktop.setCount == 2)
    }

    @Test func turningOffRestoresEveryDisplay() async throws {
        let (engine, _) = try makeEngine()
        desktop.connected = [Displays.builtin, Displays.external]
        for space in ["", "S2", ""] { await visit(space, engine, enabled: true, builtinOnly: false) }
        await visit("", engine, enabled: false, builtinOnly: false)
        for display in ["BUILTIN", "EXTERNAL"] {
            #expect(desktop["", on: display]?.url == photo)
            #expect(desktop["", on: display]?.options == options)
        }
        #expect(engine.spacesToVisit == ["Desktop 2", "Desktop 2 on Studio Display"])
        await visit("S2", engine, enabled: false, builtinOnly: false)
        #expect(desktop["S2", on: "EXTERNAL"]?.url == photo)
        #expect(engine.spacesToVisit.isEmpty)
        #expect(try renders().isEmpty)
    }

    @Test func turningOnMacBookScreenOnlyRestoresExternalDisplays() async throws {
        let (engine, _) = try makeEngine()
        desktop.connected = [Displays.builtin, Displays.external]
        await engine.sync(enabled: true, builtinOnly: false, corners: .off)
        #expect(try renders().count == 2)
        await engine.sync(enabled: true, builtinOnly: true, corners: .off)
        #expect(desktop["", on: "EXTERNAL"]?.url == photo)
        #expect(desktop["", on: "EXTERNAL"]?.options == options)
        #expect(desktop[""]?.url != photo)
        #expect(engine.statuses == statuses(.applied, Displays.builtin))
        #expect(try renders().count == 1)
    }

    @Test func aDisplayDisconnectedWhileOnIsRestoredWhenItReturns() async throws {
        let (engine, _) = try makeEngine()
        desktop.connected = [Displays.builtin, Displays.external]
        await engine.sync(enabled: true, builtinOnly: false, corners: .off)
        desktop.connected = [Displays.builtin]
        await engine.sync(enabled: false, builtinOnly: false, corners: .off)
        #expect(engine.spacesToVisit == ["a disconnected display"])
        desktop.connected = [Displays.builtin, Displays.external]
        await engine.sync(enabled: false, builtinOnly: false, corners: .off)
        #expect(desktop["", on: "EXTERNAL"]?.url == photo)
        #expect(engine.spacesToVisit.isEmpty)
    }

    @Test func strayRendersAreDeletedAndTheShownOneKept() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        let shown = try #require(desktop[""]?.url)
        let rendersFolder = folder.appending(path: "State/Renders")
        for stray in ["v0-0123456789ab.png", "\(shown.lastPathComponent).partial"] {
            try Data("stray".utf8).write(to: rendersFolder.appending(path: stray))
        }
        let (relaunched, _) = try makeEngine()
        #expect(try renders() == [shown.lastPathComponent])
        await relaunched.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 1)
    }

    @Test func aRenderLeftByAFailedSetIsDeleted() async throws {
        let (engine, _) = try makeEngine()
        desktop.failsToSet = true
        await engine.sync(enabled: true, corners: .off)
        #expect(engine.statuses.count == 1 && engine.statuses[0].status != .applied)
        #expect(try renders().count == 1)
        desktop.failsToSet = false
        await engine.sync(enabled: true, corners: .high)
        let shown = try #require(desktop[""]?.url)
        #expect(try renders() == [shown.lastPathComponent])
    }

    @Test func turningOffDuringARenderRestoresOnceTheRenderIsSet() async throws {
        let (engine, _) = try makeEngine()
        let turnOff = StartedSync()
        whenPaintingStarts(engine) { turnOff.task = Task { await engine.sync(enabled: false, corners: .off) } }
        await engine.sync(enabled: true, corners: .off)
        try await #require(turnOff.task).value
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == options)
        #expect(engine.statuses.isEmpty)
        #expect(engine.painting == nil)
        #expect(try renders().isEmpty)
    }

    @Test func aSpaceSwitchDuringARenderPaintsTheSpaceNowOnScreen() async throws {
        let (engine, store) = try makeEngine()
        let desktop = self.desktop
        whenPaintingStarts(engine) { desktop.currentSpace = "S2" }
        await engine.sync(enabled: true, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(store.isRender(try #require(desktop["S2"]?.url)))
        #expect(store.applied.keys.map(\.space) == ["S2"])
        #expect(engine.statuses == statuses(.applied, Displays.builtin))
    }

    @Test func aRenderNamedOnlyByTheWallpaperStoreIsNeverTakenForTheOriginal() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        desktop.reportsNoFile = true
        await engine.sync(enabled: true, corners: .high)
        await engine.sync(enabled: false, corners: .off)
        desktop.reportsNoFile = false
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == options)
        #expect(try renders().isEmpty)
    }

    @Test func aRecordThatCannotBeSavedSetsNothingAndIsRetried() async throws {
        let (engine, _) = try makeEngine()
        let state = folder.appending(path: "State").path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: state)
        await engine.sync(enabled: true, corners: .off)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: state)
        #expect(engine.statuses.count == 1 && engine.statuses[0].status != .applied)
        #expect(desktop[""]?.url == photo)
        #expect(desktop.setCount == 0)

        await engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 1)
        let (relaunched, _) = try makeEngine()
        await relaunched.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == options)
    }

    @Test func aPlacementPickedWhileOnIsRenderedAndRestored() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        let fit = DesktopOptions(scaling: 3, allowClipping: false, fillColor: NSColor(calibratedRed: 0.25, green: 0.41, blue: 0.67, alpha: 1))
        desktop[""] = (desktop[""]?.url, fit)
        await engine.sync(enabled: true, corners: .off)
        #expect(desktop.setCount == 2)
        #expect(desktop[""]?.options == fit)
        await engine.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(desktop[""]?.options == fit)
    }

    @Test func aRenderAnotherSpaceStillShowsIsKept() async throws {
        let (engine, _) = try makeEngine()
        await engine.sync(enabled: true, corners: .off)
        let shown = try #require(desktop[""]?.url)
        // As with Show on All Spaces: macOS put the render on a Space OpenNotch has no record for.
        desktop["S2"] = (shown, options)
        await engine.sync(enabled: false, corners: .off)
        #expect(desktop[""]?.url == photo)
        #expect(try renders() == [shown.lastPathComponent])
    }
}
