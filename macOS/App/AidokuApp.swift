import AppKit
import SwiftUI

@main
struct AidokuMacApp: App {
    @StateObject private var model = MacModel()
    var body: some Scene {
        WindowGroup("Aidoku — Native macOS Preview") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
                        await NativeSmoke.run()
                    } else { await model.start() }
                }
                .onOpenURL { url in Task { await model.importFile(url) } }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Comic or Source…") { model.chooseFile() }.keyboardShortcut("o")
            }
            CommandMenu("Reader") {
                Button("向左翻页") { model.turnVisual(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(!model.showReader)
                Button("向右翻页") { model.turnVisual(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(!model.showReader)
                Button("下一页") { model.movePage(1) }.keyboardShortcut(.space, modifiers: []).disabled(!model.showReader)
                Button("上一页") { model.movePage(-1) }.keyboardShortcut(.pageUp, modifiers: []).disabled(!model.showReader)
                Button("下一屏") { model.movePage(1) }.keyboardShortcut(.pageDown, modifiers: []).disabled(!model.showReader)
                Divider()
                Picker("阅读模式", selection: $model.readerMode) {
                    ForEach(NativeReaderMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("从右向左", isOn: $model.rightToLeft)
            }
        }
        Settings { NativeReaderSettings(model: model).padding(24).frame(width: 400) }
    }
}
