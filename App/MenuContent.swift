import OpenNotchCore
import OpenNotchSystem
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Toggle("Black Menu Bar", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
        // A status's detail sits in a submenu, so however long it is, the menu keeps its width.
        ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
            if let detail = line.detail {
                Menu(line.title) { Text(detail) }
            } else {
                Text(line.title)
            }
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
