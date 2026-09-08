import AppKit
import AidokuRunner
import Combine
import PDFKit
import ZIPFoundation

struct SavedBook: Codable, Identifiable {
    var id = UUID()
    var title: String
    var sourceKey: String?
    var mangaKey: String?
    var bookmark: Data?
    var chapterKey: String?
    var page = 0
}

@MainActor
final class MacModel: ObservableObject {
    @Published var sources: [AidokuRunner.Source] = []
    @Published var sourceKey = ""
    @Published var query = ""
    @Published var results: [AidokuRunner.Manga] = []
    @Published var manga: AidokuRunner.Manga?
    @Published var books: [SavedBook] = []
    @Published var externalSources: [ExternalSourceInfo] = []
    @Published var listURL = ""
    @Published var busy = false
    @Published var error: String?
    @Published var image: NSImage?
    @Published var pageText: String?
    @Published var page = 0
    @Published var pageCount = 0
    @Published var readerTitle = ""
    @Published var showReader = false
    @Published var hasNextResults = false

    private let root: URL
    private var started = false
    private var activeBook: UUID?
    private var pages: [AidokuRunner.Page] = []
    private var archive: Archive?
    private var localPaths: [String] = []
    private var folder: URL?
    private var pdf: PDFDocument?
    private var activeSource: AidokuRunner.Source?
    private var accessURL: URL?
    private var hasAccess = false
    private var imageTask: Task<Void, Never>?
    private var generation = UUID()
    private var resultPage = 1

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.aidoku.macOS")
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
            let libraryURL = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                books = try JSONDecoder().decode([SavedBook].self, from: Data(contentsOf: libraryURL))
            }
            for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil) {
                do { sources.append(try await AidokuRunner.Source(url: url)) }
                catch { self.error = "Source \(url.lastPathComponent) could not load: \(error.localizedDescription)" }
            }
            sources.sort { $0.name < $1.name }
            sourceKey = sources.first?.key ?? ""
            listURL = UserDefaults.standard.string(forKey: "mac.sourceListURL") ?? ""
        } catch { self.error = error.localizedDescription }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.message = "Open CBZ, ZIP, PDF, an image folder, or a new-format AIX source"
        if panel.runModal() == .OK, let url = panel.url { Task { await importFile(url) } }
    }

    func importFile(_ url: URL) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if url.pathExtension.lowercased() == "aix" { try await installSource(url); return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let title = url.deletingPathExtension().lastPathComponent
            let series = LocalFileNameParser.parseMangaSeries(from: title)
            let book = SavedBook(title: series.isEmpty ? title : "\(series) · \(title)", bookmark: bookmark)
            try openLocal(url, book: book)
            books.append(book)
            save()
        } catch { self.error = error.localizedDescription }
    }

    func installSource(_ url: URL) async throws {
        let temporary = root.appendingPathComponent("Import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var packageURL = url
        var downloaded: URL?
        let access = url.isFileURL && url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            if let downloaded { try? FileManager.default.removeItem(at: downloaded) }
        }
        if !url.isFileURL {
            guard ["https", "http"].contains(url.scheme ?? "") else { throw NativeError.message("Unsupported source URL.") }
            let (location, response) = try await URLSession.shared.download(from: url)
            downloaded = location
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw NativeError.message("Source download failed.")
            }
            packageURL = location
        }
        try NativeFiles.unpackSource(packageURL, to: temporary)
        let payload = temporary.appendingPathComponent("Payload")
        guard FileManager.default.fileExists(atPath: payload.appendingPathComponent("source.json").path) else {
            throw NativeError.message("This package uses the legacy source format, which this macOS preview does not yet support.")
        }
        let source = try await AidokuRunner.Source(url: payload)
        guard NativeFiles.validSourceKey(source.key) else { throw NativeError.message("Invalid source identifier.") }
        guard !sources.contains(where: { $0.key == source.key }) else { throw NativeError.message("This source is already installed.") }
        let target = root.appendingPathComponent("Sources").appendingPathComponent(source.key)
        try FileManager.default.moveItem(at: payload, to: target)
        do {
            let loaded = try await AidokuRunner.Source(url: target)
            sources.append(loaded)
            sources.sort { $0.name < $1.name }
            sourceKey = loaded.key
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    func loadSourceList() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let url = URL(string: listURL), ["https", "http"].contains(url.scheme ?? "") else {
                throw NativeError.message("Enter an HTTP or HTTPS source-list URL.")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw NativeError.message("Could not download the source list.")
            }
            let list = try JSONDecoder().decode(CodableSourceList.self, from: data).into(url: url)
            externalSources = list.sources
            UserDefaults.standard.set(listURL, forKey: "mac.sourceListURL")
        } catch { self.error = error.localizedDescription }
    }

    func install(_ info: ExternalSourceInfo) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let appVersion = SemanticVersion("0.9")
            if let minimum = info.minAppVersion, appVersion < SemanticVersion(minimum) {
                throw NativeError.message("This source requires Aidoku \(minimum).")
            }
            if let maximum = info.maxAppVersion, appVersion > SemanticVersion(maximum) {
                throw NativeError.message("This source supports Aidoku only up to \(maximum).")
            }
            guard let url = info.fileURL else { throw NativeError.message("No download URL in source list.") }
            try await installSource(url)
        } catch { self.error = error.localizedDescription }
    }

    func search(next: Bool = false) async {
        guard !busy, let source = sources.first(where: { $0.key == sourceKey }) else { return }
        busy = true
        defer { busy = false }
        do {
            let requestedPage = next ? resultPage + 1 : 1
            let result = try await source.getSearchMangaList(query: query, page: requestedPage, filters: [])
            resultPage = requestedPage
            results = next ? results + result.entries : result.entries
            hasNextResults = result.hasNextPage
        } catch { self.error = error.localizedDescription }
    }

    func selectManga(_ item: AidokuRunner.Manga, sourceKey: String? = nil) async {
        guard !busy, let source = sources.first(where: { $0.key == (sourceKey ?? item.sourceKey) }) else { return }
        busy = true
        defer { busy = false }
        do {
            manga = try await source.getMangaUpdate(manga: item, needsDetails: true, needsChapters: true)
            activeSource = source
        } catch { self.error = error.localizedDescription }
    }

    func addToLibrary() {
        guard let manga, let source = activeSource else { return }
        if let book = books.first(where: { $0.sourceKey == source.key && $0.mangaKey == manga.key }) {
            activeBook = book.id
        } else {
            let book = SavedBook(title: manga.title, sourceKey: source.key, mangaKey: manga.key)
            books.append(book)
            activeBook = book.id
            save()
        }
    }

    func openBook(_ book: SavedBook) async {
        do {
            if let bookmark = book.bookmark {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
                try openLocal(url, book: book)
            } else if let sourceKey = book.sourceKey, let key = book.mangaKey {
                guard sources.contains(where: { $0.key == sourceKey }) else {
                    throw NativeError.message("Install this book's source first: \(sourceKey)")
                }
                await selectManga(.init(sourceKey: sourceKey, key: key, title: book.title), sourceKey: sourceKey)
                activeBook = book.id
            }
        } catch { self.error = error.localizedDescription }
    }

    func readChapter(_ chapter: AidokuRunner.Chapter) async {
        guard !busy, let manga, let source = activeSource else { return }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await source.getPageList(manga: manga, chapter: chapter)
            guard !loaded.isEmpty else { throw NativeError.message("This chapter has no pages.") }
            resetReader()
            activeSource = source
            pages = loaded
            pageCount = loaded.count
            readerTitle = manga.title + " · " + (chapter.title ?? chapter.key)
            addToLibrary()
            var resumePage = 0
            if let index = books.firstIndex(where: { $0.id == activeBook }) {
                if books[index].chapterKey == chapter.key { resumePage = books[index].page }
                books[index].chapterKey = chapter.key
            }
            showReader = true
            renderPage(resumePage)
        } catch { self.error = error.localizedDescription }
    }

    private func openLocal(_ url: URL, book: SavedBook) throws {
        resetReader()
        hasAccess = url.startAccessingSecurityScopedResource()
        accessURL = url
        let directory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        if directory {
            folder = url
            localPaths = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { NativeFiles.imageExtensions.contains($0.pathExtension.lowercased()) }
                .map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            pageCount = localPaths.count
        } else if url.pathExtension.lowercased() == "pdf" {
            pdf = PDFDocument(url: url)
            pageCount = pdf?.pageCount ?? 0
        } else if ["cbz", "zip"].contains(url.pathExtension.lowercased()) {
            let opened = try Archive(url: url, accessMode: .read)
            archive = opened
            localPaths = NativeFiles.imagePaths(in: opened)
            pageCount = localPaths.count
        } else { throw NativeError.message("Supported formats: CBZ, ZIP, PDF, image folder, AIX.") }
        guard pageCount > 0 else { throw NativeError.message("No readable pages found.") }
        activeBook = book.id
        readerTitle = book.title
        showReader = true
        renderPage(book.page)
    }

    private func resetReader() {
        imageTask?.cancel()
        generation = UUID()
        if hasAccess { accessURL?.stopAccessingSecurityScopedResource() }
        hasAccess = false
        accessURL = nil
        pages = []; localPaths = []; folder = nil; pdf = nil; archive = nil
        image = nil; pageText = nil; pageCount = 0; page = 0; showReader = false
    }

    func movePage(_ delta: Int) { renderPage(page + delta) }

    func renderPage(_ requested: Int) {
        guard pageCount > 0 else { return }
        imageTask?.cancel()
        let token = UUID()
        generation = token
        let index = min(max(0, requested), pageCount - 1)
        page = index
        image = nil; pageText = nil
        imageTask = Task {
            do {
                let result: NSImage?
                var text: String?
                if let pdf {
                    result = pdf.page(at: index)?.thumbnail(of: NSSize(width: 1800, height: 2600), for: .mediaBox)
                } else if let archive, let entry = archive.entry(at: localPaths[index]) {
                    result = NSImage(data: try NativeFiles.data(archive: archive, entry: entry))
                } else if let folder {
                    let url = folder.appendingPathComponent(localPaths[index])
                    guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= NativeFiles.entryLimit else {
                        throw NativeError.message("Image exceeds 100 MB.")
                    }
                    result = NSImage(contentsOf: url)
                } else {
                    switch pages[index].content {
                    case .text(let value): text = value; result = nil
                    case .image(let value): result = value.image
                    case .url(let url, let context):
                        result = try await fetchImage(url, context: context)
                    case .zipFile:
                        throw NativeError.message("Online ZIP-backed pages are not yet supported.")
                    }
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                guard result != nil || text != nil else { throw NativeError.message("Page image could not be decoded.") }
                image = result
                pageText = text
                if let i = books.firstIndex(where: { $0.id == activeBook }) { books[i].page = index; save() }
            } catch is CancellationError {
            } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }

    private func fetchImage(_ url: URL, context: PageContext?) async throws -> NSImage? {
        guard ["http", "https"].contains(url.scheme ?? "") else { throw NativeError.message("Unsupported online page URL.") }
        var request = URLRequest(url: url)
        if let source = activeSource, source.features.providesImageRequests {
            request = try await source.getImageRequest(url: url.absoluteString, context: context)
        }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw NativeError.message("Image request failed. The source may require browser authentication.")
        }
        guard data.count <= NativeFiles.entryLimit, let platform = PlatformImage(data: data) else {
            throw NativeError.message("Invalid or oversized page image.")
        }
        if let source = activeSource, source.features.processesPages {
            let ref = try await source.store(value: platform)
            do {
                let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
                let processed = try await source.processPageImage(response: .init(
                    code: response.statusCode, headers: headers,
                    request: .init(url: request.url, headers: request.allHTTPHeaderFields ?? [:]), image: ref), context: context)
                try await source.remove(value: ref)
                return processed?.image ?? platform.image
            } catch { try? await source.remove(value: ref); throw error }
        }
        return platform.image
    }

    func removeBook(_ book: SavedBook) {
        books.removeAll { $0.id == book.id }
        if activeBook == book.id { activeBook = nil }
        save()
    }

    private func save() {
        do { try JSONEncoder().encode(books).write(to: root.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "Could not save library: \(error.localizedDescription)" }
    }
}
