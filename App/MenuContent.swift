import OpenNotchCore
import OpenNotchSystem
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Toggle("Black Menu Bar", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
        ForEach(Array(statusLines.enumerated()), id: \.offset) { Text($0.element) }
        if !model.spacesToVisit.isEmpty {
            Text("Visit to restore: \(model.spacesToVisit.formatted(.list(type: .and)))")
        }
        Divider()
        Toggle("MacBook Screen Only", isOn: Binding(get: { model.builtinOnly }, set: { model.setBuiltinOnly($0) }))
        Picker("Rounded Corners", selection: Binding(get: { model.corners }, set: { model.setCorners($0) })) {
            ForEach(CornerStyle.allCases, id: \.self) { style in
                Text(style.title).tag(style)
            }
        }
        Picker("Bar Color in Light Mode", selection: Binding(get: { model.lightBand }, set: { model.setBand($0, for: .light) })) {
            ForEach(BandColor.allCases, id: \.self) { color in
                Text(color.title).tag(color)
            }
        }
        Picker("Bar Color in Dark Mode", selection: Binding(get: { model.darkBand }, set: { model.setBand($0, for: .dark) })) {
            ForEach(BandColor.allCases, id: \.self) { color in
                Text(color.title).tag(color)
            }
        }
        Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Button("Hide Menu Bar Icon") { model.isIconVisible = false }
        Divider()
        Button("Quit OpenNotch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLines: [String] {
        if let startupError = model.startupError { return [startupError] }
        if let painting = model.painting { return [painting.summary] }
        if model.statuses.isEmpty {
            guard model.isEnabled else { return ["Off"] }
            return [model.builtinOnly ? "No built-in display found" : "No display found"]
        }
        return model.statuses.map { "\($0.name): \($0.status.summary)" }
    }
}

extension NotchStatus {
    var summary: String {
        switch self {
        case .off: "Off"
        case .applied: "On"
        case .fullScreenSpace: "Paused in full-screen Spaces"
        case .unsupportedWallpaper: "This wallpaper type isn't supported yet"
        case .failed(let message): "Couldn't apply: \(message)"
        }
    }
}

extension RenderProgress {
    var summary: String {
        frameCount > 1 ? "Painting wallpaper… \(framesDone) of \(frameCount) frames" : "Painting wallpaper…"
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

extension BandColor {
    var title: String {
        switch self {
        case .black: "Black"
        case .graphite: "Graphite"
        case .silver: "Silver"
        case .white: "White"
        }
    }
}
