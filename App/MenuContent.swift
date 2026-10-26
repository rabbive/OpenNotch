import OpenNotchCore
import OpenNotchSystem
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Toggle("Black Menu Bar", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
        Text(model.status.summary)
        if !model.spacesToVisit.isEmpty {
            Text("Visit to restore: \(model.spacesToVisit.formatted(.list(type: .and)))")
        }
        Divider()
        Picker("Rounded Corners", selection: Binding(get: { model.corners }, set: { model.setCorners($0) })) {
            ForEach(CornerStyle.allCases, id: \.self) { style in
                Text(style.title).tag(style)
            }
        }
        Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Divider()
        Button("Quit OpenNotch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension NotchStatus {
    var summary: String {
        switch self {
        case .off: "Off"
        case .applied: "On for the built-in display"
        case .noBuiltinDisplay: "No built-in display found"
        case .fullScreenSpace: "Paused in full-screen Spaces"
        case .dynamicWallpaper: "Dynamic wallpapers aren't supported yet"
        case .unsupportedWallpaper: "This wallpaper type isn't supported yet"
        case .failed(let message): "Couldn't apply: \(message)"
        }
    }
}

extension CornerStyle {
    var title: String {
        switch self {
        case .off: "Off"
        case .small: "Small"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}
