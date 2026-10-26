import SwiftUI

@main
struct OpenNotchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OpenNotch", systemImage: "rectangle.topthird.inset.filled") {
            MenuContent(model: model)
        }
    }
}
