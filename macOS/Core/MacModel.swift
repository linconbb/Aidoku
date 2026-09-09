import AppKit
import AidokuRunner
import Combine
import PDFKit
import ZIPFoundation
import UniformTypeIdentifiers

struct SavedBook: Codable, Identifiable {
    var id = UUID()
    var title: String
    var sourceKey: String?
    var mangaKey: String?
    var bookmark: Data?
    var chapterKey: String?
    var page = 0
}

struct NativeInstalledSource: Identifiable {
    var id: String
    var name: String
    var version: Int
    var disabled: Bool
}

struct NativeReaderContent {
    var image: NSImage?
    var text: String?
}
final class NativePageCacheEntry {
    let content: NativeReaderContent
    init(_ content: NativeReaderContent) { self.content = content }
}

@MainActor
final class MacModel: ObservableObject {
    @Published var installedSources: [NativeInstalledSource] = []
    @Published var savedSourceLists: [String] = []
    private var disabledSourceKeys: Set<String> = []
    private var listsByURL: [String: [ExternalSourceInfo]] = [:]
    private var exportTask: Task<Void, Never>?
    @Published var sources: [AidokuRunner.Source] = []
    @Published var sourceKey = "" {
        didSet {
            if oldValue != sourceKey { results = []; hasNextResults = false; resultPage = 1; home = nil; listings = []; browseTitle = ""; loadedBrowseSource = ""; browseLoading = false; browseGeneration = UUID() }
        }
    }
    @Published var home: AidokuRunner.Home?
    @Published var listings: [AidokuRunner.Listing] = []
    @Published var browseTitle = ""
    @Published var browseLoading = false
    @Published var browseError: String?
    @Published var posterGrid = true
    let coverCache = NSCache<NSString, NSImage>()
    var loadedBrowseSource = ""
    var browseGeneration = UUID()
    var selectedListing: AidokuRunner.Listing?
    var browseFilters: [AidokuRunner.FilterValue]?
    var browsePage = 1
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

    @Published var readerMode: NativeReaderMode = .single {
        didSet { preferences.set(readerMode.rawValue, forKey: "mac.reader.mode") }
    }
    @Published var rightToLeft = false {
        didSet { preferences.set(rightToLeft, forKey: "mac.reader.rtl") }
    }
    @Published var coverAlone = true {
        didSet { preferences.set(coverAlone, forKey: "mac.reader.coverAlone") }
    }
    @Published var readerFit: NativeReaderFit = .page {
        didSet { preferences.set(readerFit.rawValue, forKey: "mac.reader.fit") }
    }
    @Published var readerBackground: NativeReaderBackground = .dark {
        didSet { preferences.set(readerBackground.rawValue, forKey: "mac.reader.background") }
    }
    @Published var readerZoom = 1.0
    @Published var readerSession = UUID()
    @Published var pageLoading = false
    @Published var pageError: String?
    @Published var currentChapterKey: String?
    @Published var exportBusy = false
    @Published var exportProgress = ""
    @Published var libraryQuery = ""
    private let pageCache = NSCache<NSNumber, NativePageCacheEntry>()
    private var pageLoads: [Int: Task<NativeReaderContent, Error>] = [:]
    private let preferences: UserDefaults
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
    private var resultQuery = ""
    private var resultSourceKey = ""

    init(root: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.readerMode = NativeReaderMode(rawValue: preferences.string(forKey: "mac.reader.mode") ?? "") ?? .single
        self.rightToLeft = preferences.bool(forKey: "mac.reader.rtl")
        self.coverAlone = preferences.object(forKey: "mac.reader.coverAlone") as? Bool ?? true
        self.readerFit = NativeReaderFit(rawValue: preferences.string(forKey: "mac.reader.fit") ?? "") ?? .page
        self.readerBackground = NativeReaderBackground(rawValue: preferences.string(forKey: "mac.reader.background") ?? "") ?? .dark
        self.disabledSourceKeys = Set(preferences.stringArray(forKey: "mac.disabledSources") ?? [])
        self.savedSourceLists = preferences.stringArray(forKey: "mac.sourceLists") ??
            (preferences.string(forKey: "mac.sourceListURL").map { [$0] } ?? [])
        coverCache.countLimit = 100
        coverCache.totalCostLimit = 64 * 1024 * 1024
        pageCache.countLimit = 12
        pageCache.totalCostLimit = 128 * 1024 * 1024
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
                do {
                    if disabledSourceKeys.contains(url.lastPathComponent) {
                        let data = try Data(contentsOf: url.appendingPathComponent("source.json"))
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let info = json?["info"] as? [String: Any]
                        installedSources.append(.init(id: url.lastPathComponent, name: info?["name"] as? String ?? url.lastPathComponent,
                                                      version: info?["version"] as? Int ?? 0, disabled: true))
                    } else {
                        let source = try await AidokuRunner.Source(url: url)
                        sources.append(source)
                        installedSources.append(.init(id: source.key, name: source.name, version: source.version, disabled: false))
                    }
                }
                catch { self.error = "Source \(url.lastPathComponent) could not load: \(error.localizedDescription)" }
            }
            sources.sort { $0.name < $1.name }
            installedSources.sort { $0.name < $1.name }
            sourceKey = sources.first?.key ?? ""
            listURL = preferences.string(forKey: "mac.sourceListURL") ?? ""
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
            if let existing = books.first(where: { book in
                guard let data = book.bookmark else { return false }
                var stale = false
                return (try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale))?.standardizedFileURL == url.standardizedFileURL
            }) {
                try openLocal(url, book: existing)
                return
            }
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
        let target = root.appendingPathComponent("Sources").appendingPathComponent(source.key)
        let backup = root.appendingPathComponent("SourceBackup-\(UUID().uuidString)")
        let replacing = FileManager.default.fileExists(atPath: target.path)
        if replacing { try FileManager.default.moveItem(at: target, to: backup) }
        do {
            try FileManager.default.moveItem(at: payload, to: target)
            let loaded = try await AidokuRunner.Source(url: target)
            if activeSource?.key == loaded.key {
                closeReader()
                activeSource = loaded
            }
            sources.removeAll { $0.key == loaded.key }
            let disabled = disabledSourceKeys.contains(loaded.key)
            if !disabled { sources.append(loaded); sourceKey = loaded.key }
            sources.sort { $0.name < $1.name }
            installedSources.removeAll { $0.id == loaded.key }
            installedSources.append(.init(id: loaded.key, name: loaded.name, version: loaded.version, disabled: disabled))
            installedSources.sort { $0.name < $1.name }
            if replacing { try? FileManager.default.removeItem(at: backup) }
        } catch {
            try? FileManager.default.removeItem(at: target)
            if replacing { try FileManager.default.moveItem(at: backup, to: target) }
            throw error
        }
    }

    func setSourceEnabled(_ record: NativeInstalledSource, enabled: Bool) async {
        guard !busy, NativeFiles.validSourceKey(record.id) else { return }
        busy = true
        defer { busy = false }
        do {
            if enabled {
                let source = try await AidokuRunner.Source(url: root.appendingPathComponent("Sources").appendingPathComponent(record.id))
                sources.removeAll { $0.key == record.id }
                sources.append(source)
                sources.sort { $0.name < $1.name }
                disabledSourceKeys.remove(record.id)
                sourceKey = source.key
            } else {
                disabledSourceKeys.insert(record.id)
                sources.removeAll { $0.key == record.id }
                if sourceKey == record.id { sourceKey = sources.first?.key ?? "" }
                if activeSource?.key == record.id { closeReader(); activeSource = nil; manga = nil }
            }
            if let i = installedSources.firstIndex(where: { $0.id == record.id }) { installedSources[i].disabled = !enabled }
            preferences.set(Array(disabledSourceKeys), forKey: "mac.disabledSources")
            results = []
        } catch { self.error = error.localizedDescription }
    }

    func removeSource(_ record: NativeInstalledSource) {
        guard !busy, NativeFiles.validSourceKey(record.id) else { return }
        do {
            let url = root.appendingPathComponent("Sources").appendingPathComponent(record.id)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            installedSources.removeAll { $0.id == record.id }
            sources.removeAll { $0.key == record.id }
            disabledSourceKeys.remove(record.id)
            preferences.set(Array(disabledSourceKeys), forKey: "mac.disabledSources")
            if activeSource?.key == record.id { closeReader(); activeSource = nil; manga = nil }
            if sourceKey == record.id { sourceKey = sources.first?.key ?? "" }
            results = []
        } catch { self.error = error.localizedDescription }
    }

    private func fetchSourceList(_ url: URL) async throws -> [ExternalSourceInfo] {
        func decode(_ url: URL) async throws -> [ExternalSourceInfo] {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw NativeError.message("Could not download the source list.")
            }
            let base = response.url ?? url
            if let list = try? JSONDecoder().decode(CodableSourceList.self, from: data) { return list.into(url: base).sources }
            return try JSONDecoder().decode([ExternalSourceInfo].self, from: data).map { $0.with(sourceUrl: base) }
        }
        do { return try await decode(url) }
        catch {
            if url.pathExtension.isEmpty { return try await decode(url.appendingPathComponent("index.min.json")) }
            throw error
        }
    }

    private func mergeSourceLists() {
        var byKey: [String: ExternalSourceInfo] = [:]
        for url in savedSourceLists {
            for info in listsByURL[url] ?? [] where byKey[info.id] == nil || byKey[info.id]!.version < info.version { byKey[info.id] = info }
        }
        externalSources = byKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func loadSourceList() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let url = URL(string: listURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["https", "http"].contains(url.scheme ?? "") else {
                throw NativeError.message("Enter an HTTP or HTTPS source-list URL.")
            }
            listsByURL[url.absoluteString] = try await fetchSourceList(url)
            if !savedSourceLists.contains(url.absoluteString) { savedSourceLists.append(url.absoluteString) }
            preferences.set(savedSourceLists, forKey: "mac.sourceLists")
            preferences.set(url.absoluteString, forKey: "mac.sourceListURL")
            mergeSourceLists()
        } catch { self.error = error.localizedDescription }
    }

    func refreshSourceLists() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var failures: [String] = []
        for value in savedSourceLists {
            guard let url = URL(string: value) else { continue }
            do { listsByURL[value] = try await fetchSourceList(url) }
            catch { failures.append(value + ": " + error.localizedDescription) }
        }
        mergeSourceLists()
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func removeSourceList(_ url: String) {
        savedSourceLists.removeAll { $0 == url }
        listsByURL[url] = nil
        preferences.set(savedSourceLists, forKey: "mac.sourceLists")
        mergeSourceLists()
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
        let token = UUID()
        browseGeneration = token
        home = nil
        selectedListing = nil
        browseFilters = nil
        browseLoading = false
        browseTitle = query.isEmpty ? "全部漫画" : "搜索结果"
        browseError = nil
        defer { busy = false }
        do {
            let searchQuery = query
            let append = next && resultSourceKey == source.key && resultQuery == searchQuery
            let requestedPage = append ? resultPage + 1 : 1
            let result = try await source.getSearchMangaList(query: searchQuery, page: requestedPage, filters: [])
            guard browseGeneration == token, sourceKey == source.key, query == searchQuery else { return }
            resultPage = requestedPage
            resultQuery = searchQuery
            resultSourceKey = source.key
            var seen = Set<String>()
            results = (append ? results + result.entries : result.entries).filter { seen.insert($0.key).inserted }
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
            currentChapterKey = nil
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
            currentChapterKey = chapter.key
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
        currentChapterKey = nil
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
        readerSession = UUID()
        pageLoads.values.forEach { $0.cancel() }
        pageLoads.removeAll()
        pageCache.removeAllObjects()
        pageLoading = false
        pageError = nil
        if hasAccess { accessURL?.stopAccessingSecurityScopedResource() }
        hasAccess = false
        accessURL = nil
        pages = []; localPaths = []; folder = nil; pdf = nil; archive = nil
        image = nil; pageText = nil; pageCount = 0; page = 0; showReader = false
    }

    var visiblePageIndices: [Int] {
        NativeReaderLayout.indices(page: page, count: pageCount, mode: readerMode, coverAlone: coverAlone)
    }
    func pageDestination(_ delta: Int) -> Int? {
        NativeReaderLayout.destination(page: page, count: pageCount, mode: readerMode, coverAlone: coverAlone, delta: delta)
    }
    func movePage(_ delta: Int) {
        if let destination = pageDestination(delta) { renderPage(destination) }
    }
    func turnVisual(_ direction: Int) { movePage(rightToLeft ? -direction : direction) }
    func closeReader() {
        resetReader()
        currentChapterKey = nil
    }
    func recordVisiblePage(_ index: Int) {
        guard index >= 0, index < pageCount else { return }
        page = index
        if let i = books.firstIndex(where: { $0.id == activeBook }), books[i].page != index {
            books[i].page = index
            save()
        }
    }
    func renderPage(_ requested: Int) {
        guard pageCount > 0 else { return }
        imageTask?.cancel()
        let token = UUID()
        generation = token
        let session = readerSession
        let index = min(max(0, requested), pageCount - 1)
        page = index
        image = nil; pageText = nil; pageError = nil; pageLoading = true
        imageTask = Task {
            do {
                let content = try await readerContent(at: index, session: session)
                try Task.checkCancellation()
                guard generation == token else { return }
                image = content.image
                pageText = content.text
                pageLoading = false
                recordVisiblePage(index)
                // A small cache preloads the neighboring pages, not the whole chapter.
                for adjacent in [index - 1, index + 1] where (0..<pageCount).contains(adjacent) {
                    Task { _ = try? await self.readerContent(at: adjacent, session: session) }
                }
            } catch is CancellationError {
            } catch {
                if generation == token { pageLoading = false; pageError = error.localizedDescription }
            }
        }
    }

    func readerContent(at index: Int, session: UUID) async throws -> NativeReaderContent {
        guard session == readerSession, (0..<pageCount).contains(index) else { throw CancellationError() }
        if let cached = pageCache.object(forKey: NSNumber(value: index)) { return cached.content }
        if let task = pageLoads[index] { return try await task.value }
        let source = activeSource
        let task = Task<NativeReaderContent, Error> {
            try Task.checkCancellation()
            guard session == readerSession, (0..<pageCount).contains(index) else { throw CancellationError() }
            let content: NativeReaderContent
            if let pdf {
                content = .init(image: pdf.page(at: index)?.thumbnail(of: NSSize(width: 2400, height: 3400), for: .mediaBox))
            } else if let archive, let entry = archive.entry(at: localPaths[index]) {
                content = .init(image: NSImage(data: try NativeFiles.data(archive: archive, entry: entry)))
            } else if let folder {
                let url = folder.appendingPathComponent(localPaths[index])
                guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= NativeFiles.entryLimit else {
                    throw NativeError.message("Image exceeds 100 MB.")
                }
                content = .init(image: NSImage(contentsOf: url))
            } else {
                switch pages[index].content {
                case .text(let value): content = .init(text: value)
                case .image(let value): content = .init(image: value.image)
                case .url(let url, let context): content = .init(image: try await fetchImage(url, context: context, source: source))
                case .zipFile: throw NativeError.message("Online ZIP-backed pages are not yet supported.")
                }
            }
            try Task.checkCancellation()
            guard content.image != nil || content.text != nil else { throw NativeError.message("Page image could not be decoded.") }
            return content
        }
        pageLoads[index] = task
        do {
            let content = try await task.value
            guard session == readerSession else { throw CancellationError() }
            pageLoads[index] = nil
            let cost: Int
            if let image = content.image {
                let rep = image.representations.first
                let pixels = Double(rep?.pixelsWide ?? 0) * Double(rep?.pixelsHigh ?? 0)
                cost = Int(min(max(pixels * 4, 1), 256 * 1024 * 1024))
            } else { cost = content.text?.utf8.count ?? 1 }
            pageCache.setObject(NativePageCacheEntry(content), forKey: NSNumber(value: index), cost: cost)
            return content
        } catch {
            if session == readerSession { pageLoads[index] = nil }
            throw error
        }
    }

    var resumeChapter: AidokuRunner.Chapter? {
        guard let manga, let source = activeSource,
              let book = books.first(where: { $0.sourceKey == source.key && $0.mangaKey == manga.key }),
              let key = book.chapterKey else { return nil }
        return manga.chapters?.first { $0.key == key }
    }
    var orderedChapters: [AidokuRunner.Chapter] {
        // Sources conventionally return newest first; numbered chapters make order explicit.
        let chapters = manga?.chapters ?? []
        if chapters.allSatisfy({ $0.chapterNumber != nil }) {
            return chapters.sorted {
                if $0.volumeNumber != $1.volumeNumber { return ($0.volumeNumber ?? 0) < ($1.volumeNumber ?? 0) }
                return ($0.chapterNumber ?? 0) < ($1.chapterNumber ?? 0)
            }
        }
        return chapters.reversed()
    }
    func adjacentChapter(_ delta: Int) -> AidokuRunner.Chapter? {
        let chapters = orderedChapters
        guard let i = chapters.firstIndex(where: { $0.key == currentChapterKey }),
              chapters.indices.contains(i + delta) else { return nil }
        return chapters[i + delta]
    }
    func changeChapter(_ delta: Int) async {
        guard !exportBusy, let chapter = adjacentChapter(delta) else { return }
        await readChapter(chapter)
    }

    private func fetchImage(_ url: URL, context: PageContext?, source: AidokuRunner.Source?) async throws -> NSImage? {
        guard ["http", "https"].contains(url.scheme ?? "") else { throw NativeError.message("Unsupported online page URL.") }
        var request = URLRequest(url: url)
        if let source, source.features.providesImageRequests {
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
        if let source, source.features.processesPages {
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

    func saveChapter() {
        guard pageCount > 0, !exportBusy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cbz") ?? .zip]
        panel.nameFieldStringValue = readerTitle.replacingOccurrences(of: "/", with: "-") + ".cbz"
        panel.message = "将当前章节保存为 CBZ；未完成的文件不会替换已有文件。"
        if panel.runModal() == .OK, let url = panel.url {
            exportTask = Task {
                do { try await exportCBZ(to: url) }
                catch is CancellationError { exportProgress = "已取消" }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func cancelExport() { exportTask?.cancel() }

    func exportCBZ(to destination: URL) async throws {
        guard !exportBusy, pageCount > 0 else { throw NativeError.message("No chapter available to save.") }
        exportBusy = true
        defer { exportBusy = false }
        let session = readerSession
        let count = pageCount
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("chapter.cbz")
        do {
            let archive = try Archive(url: temporary, accessMode: .create)
            for index in 0..<count {
                try Task.checkCancellation()
                let content = try await readerContent(at: index, session: session)
                guard let image = content.image, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw NativeError.message("This chapter contains text or a page that cannot be saved as an image.")
                }
                try archive.addEntry(with: String(format: "%05d.png", index + 1), type: .file, uncompressedSize: Int64(data.count)) { position, size in
                    data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
                }
                exportProgress = "保存 \(index + 1) / \(count)"
            }
        }
        try Task.checkCancellation()
        guard readerSession == session else { throw CancellationError() }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        exportProgress = "已保存 \(count) 页"
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
