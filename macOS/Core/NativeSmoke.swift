import AppKit
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
    static func run() async {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("AidokuTests-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            try require(LocalFileNameParser.getMangaChapterNumber(from: "Example Ch. 12.cbz") == 12, "shared v0.9 chapter parser")
            try require(!NativeFiles.validSourceKey("../outside"), "reject invalid source identifiers")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 24,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = bitmap.representation(using: .png, properties: [:])!
            let cbz = temp.appendingPathComponent("Example Ch. 12.cbz")
            do {
                let archive = try Archive(url: cbz, accessMode: .create)
                for path in ["10.png", "2.png", "1.png"] {
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
                try archive.addEntry(with: "../outside", type: .file, uncompressedSize: 1) { _, _ in Data([1]) }
            }
            var rejected = false
            do { try NativeFiles.unpackSource(unsafe, to: temp.appendingPathComponent("unpacked")) }
            catch { rejected = true }
            try require(rejected, "reject archive path traversal")
            let root = temp.appendingPathComponent("Library")
            let model = MacModel(root: root)
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
            let restored = MacModel(root: root)
            await restored.start()
            try require(restored.books.count == 1 && restored.books.first?.page == 1, "persistent reading progress")
            if let payload = ProcessInfo.processInfo.environment["AIDOKU_TEST_PAYLOAD"] {
                let source = try await AidokuRunner.Source(url: URL(fileURLWithPath: payload))
                try require(source.key == "test", "official WASM fixture initialization")
                _ = try await source.getHome()
                print("PASS: official WASM getHome")
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
