@testable import OpenNotchSystem
import Testing

struct SpaceTrackerTests {
    @Test func desktopsAreNumberedLikeMissionControl() throws {
        let entry: [String: Any] = [
            "Display Identifier": "D",
            "Current Space": ["uuid": "B", "type": 0],
            "Spaces": [
                ["uuid": "", "type": 0],
                ["uuid": "A", "type": 4],
                ["uuid": "B", "type": 0],
            ],
        ]
        let spaces = try #require(SpaceTracker.parse(entry))
        #expect(spaces.current == SpaceInfo(uuid: "B", isDesktop: true, number: 2))
        #expect(spaces.all.map(\.number) == [1, nil, 2])
        #expect(spaces.all[1].isDesktop == false)
    }

    @Test func malformedEntriesYieldNothing() {
        #expect(SpaceTracker.parse(["Spaces": []]) == nil)
        #expect(SpaceTracker.parse(["Current Space": ["uuid": "gone"], "Spaces": [["uuid": "", "type": 0]]]) == nil)
    }
}
