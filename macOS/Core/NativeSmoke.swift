import AppKit
import SwiftUI
import AidokuRunner
import Foundation
import ZIPFoundation

/// Runs only with --smoke-test, in a disposable directory on the hosted runner.
@MainActor
enum NativeSmoke {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NativeError.message("TEST FAILED: " + message) }
        print("PASS: " + message)
    }
    static func testPage(_ label: String) throws -> Data {
        let image = NSImage(size: NSSize(width: 360, height: 540))
        image.lockFocus()
        (label == "1.png" ? NSColor.systemBlue : label == "2.png" ? NSColor.systemOrange : NSColor.systemGreen).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 360, height: 540)).fill()
        ("Aidoku" as NSString).draw(at: NSPoint(x: 28, y: 450),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
        (label as NSString).draw(at: NSPoint(x: 28, y: 260),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 64), .foregroundColor: NSColor.white])
        ("Native reader test" as NSString).draw(at: NSPoint(x: 28, y: 45),
            withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white])
        image.unlockFocus()
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw NativeError.message("Could not draw test page") }
        return png
    }
    static func run() async {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("AidokuTests-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            try require(LocalFileNameParser.getMangaChapterNumber(from: "Example Ch. 12.cbz") == 12, "shared v0.9 chapter parser")
            try require(!NativeFiles.validSourceKey("../outside"), "reject invalid source identifiers")
            let cbz = temp.appendingPathComponent("Example Ch. 12.cbz")
            do {
                let archive = try Archive(url: cbz, accessMode: .create)
                for path in ["10.png", "2.png", "1.png"] {
                    let png = try testPage(path)
                    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(png.count)) { position, size in
                        png.subdata(in: Int(position)..<min(Int(position)+size, png.count))
                    }
                }
            }
            let archive = try Archive(url: cbz, accessMode: .read)
            try require(NativeFiles.imagePaths(in: archive) == ["1.png", "2.png", "10.png"], "natural page ordering")
            let decoded = try NativeFiles.data(archive: archive, entry: archive["1.png"]!)
            try require(NSImage(data: decoded) != nil, "CBZ page decoding")
            let unsafe = temp.appendingPathComponent("unsafe.aix")
            do {
                let archive = try Archive(url: unsafe, accessMode: .create)
                try archive.addEntry(with: "../outside", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
            }
            var rejected = false
            do { try NativeFiles.unpackSource(unsafe, to: temp.appendingPathComponent("unpacked")) }
            catch { rejected = true }
            try require(rejected, "reject archive path traversal")
            let suiteName = "AidokuSmoke-\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suiteName)!
            defer { preferences.removePersistentDomain(forName: suiteName) }
            let root = temp.appendingPathComponent("Library")
            let model = MacModel(root: root, preferences: preferences)
            await model.start()
            await model.importFile(cbz)
            for _ in 0..<50 {
                if model.image != nil || model.error != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(model.error == nil && model.image != nil && model.pageCount == 3, "local import and native reader")
            model.movePage(1)
            for _ in 0..<50 {
                if model.image != nil || model.error != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let restored = MacModel(root: root, preferences: preferences)
            await restored.start()
            try require(restored.books.count == 1 && restored.books.first?.page == 1, "persistent reading progress")
            guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
                throw NativeError.message("App icon is missing from the bundle.")
            }
            try require(NSImage(contentsOf: iconURL) != nil, "native ICNS resource decodes")
            try require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "AppIcon", "bundle declares native app icon")
            try require(NativeReaderLayout.indices(page: 0, count: 5, mode: .spread, coverAlone: true) == [0], "spread cover displayed alone")
            try require(NativeReaderLayout.indices(page: 2, count: 5, mode: .spread, coverAlone: true) == [1, 2], "spread pairing after cover")
            try require(NativeReaderLayout.destination(page: 3, count: 5, mode: .spread, coverAlone: true, delta: -1) == 1, "backward spread navigation")
            try require(NativeReaderLayout.destination(page: 4, count: 5, mode: .spread, coverAlone: false, delta: 1) == nil, "last spread boundary")
            let session = model.readerSession
            let first = try await model.readerContent(at: 0, session: session)
            let cached = try await model.readerContent(at: 0, session: session)
            try require(first.image === cached.image, "page cache reuses decoded image")
            await model.importFile(cbz)
            try require(model.books.count == 1, "reimport does not duplicate a local book")
            let exported = temp.appendingPathComponent("exported.cbz")
            try await model.exportCBZ(to: exported)
            let exportedArchive = try Archive(url: exported, accessMode: .read)
            try require(NativeFiles.imagePaths(in: exportedArchive).count == 3, "CBZ export contains every page")
            let exportedData = try NativeFiles.data(archive: exportedArchive, entry: exportedArchive["00001.png"]!)
            try require(NSImage(data: exportedData) != nil, "exported CBZ page decodes")
            model.readerMode = .spread
            model.coverAlone = false
            model.rightToLeft = true
            model.renderPage(0)
            model.turnVisual(-1)
            try require(model.page == 2, "RTL left arrow advances one spread")
            model.turnVisual(1)
            try require(model.page == 0, "RTL right arrow returns one spread")
            let preferencesReload = MacModel(root: root, preferences: preferences)
            try require(preferencesReload.readerMode == .spread && preferencesReload.rightToLeft && !preferencesReload.coverAlone, "reading preferences persist")
            for mode in NativeReaderMode.allCases {
                model.readerMode = mode
                model.renderPage(0)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentViewController = NSHostingController(rootView: NativeReaderView(model: model).frame(width: 1000, height: 720))
                window.setContentSize(NSSize(width: 1000, height: 720))
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds: 800_000_000)
                if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    try require(rep.pixelsWide >= 900 && rep.pixelsHigh >= 600, "reader \(mode.rawValue) renders a full-size window")
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/reader-\(mode.rawValue).png"))
                    }
                }
                window.close()
            }
            model.closeReader()
            var staleRejected = false
            do { _ = try await model.readerContent(at: 0, session: session) } catch { staleRejected = true }
            try require(staleRejected, "old document load cannot overwrite new reader")
            model.readerMode = .single
            model.rightToLeft = false
            model.sources.append(.demo())
            model.sourceKey = "demo"
            model.query = "fixture"
            await model.search()
            try require(model.results.first?.key == "fixture", "shared engine search through native model")
            await model.search(next: true)
            try require(model.results.count == 1, "search pagination deduplicates repeated results")
            await model.selectManga(model.results[0])
            try require(model.manga?.chapters?.count == 4, "shared engine manga and chapters")
            await model.readChapter(model.manga!.chapters!.first!)
            for _ in 0..<50 {
                if model.pageText != nil || model.error != nil { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(model.pageText?.contains("text only chapter") == true, "shared engine page list through native reader")
            let existing = temp.appendingPathComponent("preserved.cbz")
            let sentinel = Data("original file".utf8)
            try sentinel.write(to: existing)
            var exportRejected = false
            do { try await model.exportCBZ(to: existing) } catch { exportRejected = true }
            let preservedData = try Data(contentsOf: existing)
            try require(exportRejected && preservedData == sentinel, "failed text chapter export preserves destination")
            if let payload = ProcessInfo.processInfo.environment["AIDOKU_TEST_PAYLOAD"] {
                let source = try await AidokuRunner.Source(url: URL(fileURLWithPath: payload))
                try require(source.key == "test", "official WASM fixture initialization")
                _ = try await source.getHome()
                print("PASS: official WASM getHome")
                let package = temp.appendingPathComponent("test.aix")
                do {
                    let archive = try Archive(url: package, accessMode: .create)
                    for name in ["source.json", "main.wasm"] {
                        let data = try Data(contentsOf: URL(fileURLWithPath: payload).appendingPathComponent(name))
                        try archive.addEntry(with: "Payload/" + name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                            data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
                        }
                    }
                }
                try await model.installSource(package)
                try require(model.installedSources.contains { $0.id == "test" }, "AIX package installs through native source manager")
                try await model.installSource(package)
                try require(model.installedSources.filter { $0.id == "test" }.count == 1, "source update replaces without duplicating")
                let installed = model.installedSources.first { $0.id == "test" }!
                await model.setSourceEnabled(installed, enabled: false)
                try require(!model.sources.contains { $0.key == "test" }, "source disable unloads the runtime")
                let disabledReload = MacModel(root: root, preferences: preferences)
                await disabledReload.start()
                try require(disabledReload.installedSources.first { $0.id == "test" }?.disabled == true && disabledReload.sources.isEmpty, "disabled source persists without loading WASM")
                await model.setSourceEnabled(installed, enabled: true)
                try require(model.sources.contains { $0.key == "test" }, "source enable restores runtime")
            } else { throw NativeError.message("Missing required WASM fixture path.") }
            print("ALL NATIVE SMOKE TESTS PASSED")
            fflush(stdout)
            exit(0)
        } catch {
            print("SMOKE TEST FAILURE: \(error)")
            fflush(stdout)
            try? FileManager.default.removeItem(at: temp)
            exit(1)
        }
    }
}
