import AppKit
import SwiftUI
import AidokuRunner

extension MacModel {
    func coverImage(_ value: String, sourceKey: String) async throws -> NSImage {
        let cacheKey = (sourceKey + "|" + value) as NSString
        if let cached = coverCache.object(forKey: cacheKey) { return cached }
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw NativeError.message("Unsupported cover URL")
        }
        let source = sources.first { $0.key == sourceKey }
        var request = URLRequest(url: url)
        if let source, source.features.providesImageRequests {
            request = try await source.getImageRequest(url: value, context: nil)
        }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= 20 * 1024 * 1024, let platform = PlatformImage(data: data) else {
            throw NativeError.message("Cover could not be loaded")
        }
        var image = platform.image
        if let source, source.features.processesCovers {
            let ref = try await source.store(value: platform)
            do {
                let headers = response.allHeaderFields.reduce(into: [String: String]()) {
                    $0[String(describing: $1.key)] = String(describing: $1.value)
                }
                let processed = try await source.processCoverImage(response: .init(
                    code: response.statusCode, headers: headers,
                    request: .init(url: request.url, headers: request.allHTTPHeaderFields ?? [:]), image: ref))
                try await source.remove(value: ref)
                image = processed?.image ?? image
            } catch { try? await source.remove(value: ref); throw error }
        }
        try Task.checkCancellation()
        let rep = image.representations.first
        let cost = Int(min(Double(rep?.pixelsWide ?? 0) * Double(rep?.pixelsHigh ?? 0) * 4, 64 * 1024 * 1024))
        coverCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }
}

struct NativeCoverImage: View {
    @ObservedObject var model: MacModel
    let url: String?
    let sourceKey: String
    @State private var image: NSImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: failed ? "arrow.clockwise" : "book.closed")
                        .font(.largeTitle).foregroundStyle(.secondary)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .contextMenu { if failed { Button("重新加载封面") { retry += 1 } } }
        .help(failed ? "封面加载失败，右键重试" : "")
        .task(id: sourceKey + "|" + (url ?? "") + "|\(retry)") {
            image = nil; failed = false
            guard let url else { return }
            do { image = try await model.coverImage(url, sourceKey: sourceKey) }
            catch is CancellationError { }
            catch { failed = true }
        }
    }
}
