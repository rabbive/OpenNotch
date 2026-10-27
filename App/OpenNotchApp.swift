import SwiftUI

@main
struct OpenNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra(
            "OpenNotch",
            systemImage: "rectangle.topthird.inset.filled",
            isInserted: Binding(get: { model.isIconVisible }, set: { model.isIconVisible = $0 })
        ) {
            MenuContent(model: model)
        }
    }
}

/// Opening the app while it runs brings back a hidden menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopened = Notification.Name("OpenNotchReopened")

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: Self.reopened, object: nil)
        return false
    }
}
