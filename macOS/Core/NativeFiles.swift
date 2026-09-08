import Foundation
import ZIPFoundation

enum NativeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum NativeFiles {
    static let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"])
    static let entryLimit = 100 * 1024 * 1024

    static func data(archive: Archive, entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= entryLimit else { throw NativeError.message("Archive entry exceeds 100 MB.") }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= entryLimit else { throw NativeError.message("Archive entry exceeds 100 MB.") }
            data.append(chunk)
        }
        return data
    }

    static func imagePaths(in archive: Archive) -> [String] {
        archive.filter {
            $0.type == .file && !$0.path.hasPrefix("__MACOSX/") &&
            imageExtensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
        }.map(\.path).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // Validate every member before creating files; no symlinks or traversal.
    static func unpackSource(_ url: URL, to directory: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        var total: UInt64 = 0
        for entry in archive {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                  !parts.contains(".."), entry.type != .symlink else {
                throw NativeError.message("Source package contains an unsafe path.")
            }
            total += UInt64(entry.uncompressedSize)
            guard total <= 200 * 1024 * 1024 else { throw NativeError.message("Source package exceeds 200 MB.") }
        }
        for entry in archive where entry.type == .file {
            let target = directory.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(archive: archive, entry: entry).write(to: target)
        }
    }

    static func validSourceKey(_ key: String) -> Bool {
        !key.isEmpty && key != "." && key != ".." &&
        key.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }
    }
}
