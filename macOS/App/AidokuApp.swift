import AppKit
import SwiftUI

@main
struct AidokuMacApp: App {
    @StateObject private var model = MacModel()
    var body: some Scene {
        WindowGroup("Aidoku — Native macOS Preview") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .task { await model.start() }
                .onOpenURL { url in Task { await model.importFile(url) } }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Comic or Source…") { model.chooseFile() }.keyboardShortcut("o")
            }
            CommandMenu("Reader") {
                Button("Previous Page") { model.movePage(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next Page") { model.movePage(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
    }
}
