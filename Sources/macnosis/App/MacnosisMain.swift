import AppKit
import SwiftUI

@main
struct MacnosisMain: App {
    @StateObject private var model = MacnosisAppModel()

    init() {
        if let iconURL = Bundle.main.url(forResource: "MacnosisIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            MacnosisContentView(model: model)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
