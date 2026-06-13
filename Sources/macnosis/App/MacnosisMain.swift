import SwiftUI

@main
struct MacnosisMain: App {
    @StateObject private var model = MacnosisAppModel()

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
