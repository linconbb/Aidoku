import SwiftUI
import AidokuRunner

struct RootView: View {
    @ObservedObject var model: MacModel
    @State private var section = "library"
    @State private var fitWidth = false
    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Library", systemImage: "books.vertical").tag("library")
                Label("Browse", systemImage: "magnifyingglass").tag("browse")
                Label("Sources", systemImage: "puzzlepiece.extension").tag("sources")
            }
            .navigationTitle("Aidoku")
            .navigationSplitViewColumnWidth(180)
            .toolbar { Button { model.chooseFile() } label: { Label("Open", systemImage: "plus") } }
        } detail: {
            VStack(spacing: 0) {
                if model.busy { ProgressView().padding(8) }
                if model.showReader { reader }
                else if let manga = model.manga { details(manga) }
                else if section == "sources" { sources }
                else if section == "browse" { browse }
                else { library }
            }
        }
        .onChange(of: section) { _ in model.manga = nil; model.showReader = false }
        .alert("Aidoku", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var library: some View {
        VStack {
            if model.books.isEmpty {
                Spacer()
                Image(systemName: "books.vertical").font(.system(size: 48))
                Text("Your library").font(.title)
                Text("Open a local comic, or install a source and browse.").foregroundStyle(.secondary)
                Text("Native macOS preview · Some iOS features are still being ported.").font(.caption).foregroundStyle(.secondary)
                Button("Open Comic…") { model.chooseFile() }
                Spacer()
            } else {
                List(model.books) { book in
                    HStack {
                        Button(book.title) { Task { await model.openBook(book) } }.buttonStyle(.plain)
                        Spacer()
                        Button { model.removeBook(book) } label: { Image(systemName: "minus.circle") }
                            .help("Remove from library; original file is kept")
                    }
                }
            }
        }.padding()
    }

    private var sources: some View {
        VStack(alignment: .leading) {
            Text("Sources").font(.title)
            Text("Install a new-format AIX file using Open, or enter a source-list JSON URL.")
            HStack {
                TextField("https://…/index.json", text: $model.listURL)
                Button("Load List") { Task { await model.loadSourceList() } }.disabled(model.busy)
            }
            List {
                Section("Installed") {
                    ForEach(model.sources) { source in Text(source.name) }
                }
                Section("Available") {
                    ForEach(model.externalSources, id: \.id) { source in
                        HStack {
                            Text(source.name)
                            Spacer()
                            Button(model.sources.contains(where: { $0.key == source.id }) ? "Installed" : "Install") {
                                Task { await model.install(source) }
                            }.disabled(model.busy || model.sources.contains(where: { $0.key == source.id }))
                        }
                    }
                }
            }
            Text("Legacy AIX packages, login/settings forms and Cloudflare challenge windows are not yet connected.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }

    private var browse: some View {
        VStack {
            HStack {
                Picker("Source", selection: $model.sourceKey) {
                    ForEach(model.sources) { Text($0.name).tag($0.key) }
                }
                TextField("Search manga", text: $model.query).onSubmit { Task { await model.search() } }
                Button("Search") { Task { await model.search() } }.disabled(model.busy || model.sourceKey.isEmpty)
            }
            List(model.results, id: \.key) { manga in
                Button { Task { await model.selectManga(manga) } } label: {
                    HStack {
                        if let cover = manga.cover, let url = URL(string: cover) {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() }
                                placeholder: { Image(systemName: "book.closed") }.frame(width: 50, height: 70)
                        }
                        Text(manga.title)
                    }
                }.buttonStyle(.plain)
            }
            if model.hasNextResults { Button("Load More") { Task { await model.search(next: true) } }.disabled(model.busy) }
        }.padding()
    }

    private func details(_ manga: AidokuRunner.Manga) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Back") { model.manga = nil }
                Text(manga.title).font(.title2)
                Spacer()
                Button("Add to Library") { model.addToLibrary() }
            }
            if let description = manga.description { Text(description).lineLimit(5).foregroundStyle(.secondary) }
            List(manga.chapters ?? []) { chapter in
                Button(chapter.title ?? chapter.chapterNumber.map { "Chapter \( $0 )" } ?? chapter.key) {
                    Task { await model.readChapter(chapter) }
                }.disabled(model.busy)
            }
        }.padding()
    }

    private var reader: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close Reader") { model.showReader = false }
                Text(model.readerTitle).lineLimit(1)
                Spacer()
                Toggle("Fit Width", isOn: $fitWidth).toggleStyle(.switch)
            }.padding(10)
            GeometryReader { geometry in
                ScrollView {
                    if let image = model.image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width,
                                   height: fitWidth ? geometry.size.width * image.size.height / max(image.size.width, 1) : geometry.size.height)
                    } else if let text = model.pageText {
                        Text(text).textSelection(.enabled).frame(maxWidth: 800).padding(24)
                    } else { ProgressView().frame(width: geometry.size.width, height: geometry.size.height) }
                }.id(model.page)
            }.background(Color(nsColor: .textBackgroundColor))
            HStack {
                Button("Previous") { model.movePage(-1) }.disabled(model.page == 0)
                Text("\(model.page + 1) / \(model.pageCount)").monospacedDigit()
                Button("Next") { model.movePage(1) }.disabled(model.page + 1 >= model.pageCount)
                Spacer()
            }.padding(10)
        }
    }
}
