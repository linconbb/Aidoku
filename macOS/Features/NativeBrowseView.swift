import AppKit
import SwiftUI
import AidokuRunner

struct NativeBrowseView: View {
    @ObservedObject var model: MacModel
    var automaticallyLoad = true
    private var loading: Bool { model.busy || model.browseLoading }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("源", selection: $model.sourceKey) {
                    if model.sources.isEmpty { Text("尚未安装源").tag("") }
                    ForEach(model.sources) { Text($0.name).tag($0.key) }
                }.labelsHidden().frame(maxWidth: .infinity)
                Button { Task { await model.loadBrowseHome() } } label: {
                    Image(systemName: "house")
                }.help("源首页").disabled(model.sourceKey.isEmpty || loading)
                Menu {
                    ForEach(model.listings, id: \.id) { listing in
                        Button(listing.name) { Task { await model.openListing(listing) } }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .help("分类列表").disabled(model.listings.isEmpty || loading)
                Button { model.posterGrid.toggle() } label: {
                    Image(systemName: model.posterGrid ? "list.bullet" : "square.grid.2x2")
                }.help(model.posterGrid ? "切换列表" : "切换海报墙")
            }
            HStack {
                TextField("搜索漫画", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if !loading { Task { await model.search() } } }
                Button { Task { await model.search() } } label: { Image(systemName: "magnifyingglass") }
                    .disabled(loading || model.sourceKey.isEmpty)
            }
            if model.browseLoading { ProgressView().controlSize(.small) }
            if let error = model.browseError {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button("重试") { Task {
                    if let listing = model.selectedListing { await model.openListing(listing) }
                    else { await model.loadBrowseHome() }
                }}.disabled(loading)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let home = model.home {
                        if home.components.isEmpty { Text("这个源的首页暂时没有内容，可尝试分类或搜索。").foregroundStyle(.secondary) }
                        ForEach(Array(home.components.enumerated()), id: \.offset) { _, component in
                            homeSection(component)
                        }
                    } else {
                        Text(model.browseTitle).font(.title2.bold())
                        mangaCollection(model.results)
                        if model.results.isEmpty && !loading {
                            Text(model.sources.isEmpty ? "请在“源”中安装漫画源。" : "暂无漫画，可尝试其他分类或关键词。")
                                .foregroundStyle(.secondary)
                        }
                        if model.hasNextResults {
                            Button("加载更多") { Task { await model.loadMoreBrowse() } }.disabled(loading)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }
        }.padding(12)
        .task(id: model.sourceKey) {
            if automaticallyLoad && model.loadedBrowseSource != model.sourceKey { await model.loadBrowseHome() }
        }
    }

    @ViewBuilder private func homeSection(_ component: HomeComponent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = component.title { Text(title).font(.title3.bold()) }
            if let subtitle = component.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            switch component.value {
            case .bigScroller(let entries, _):
                mangaCollection(entries)
            case .imageScroller(let links, _, _, _):
                linkCollection(links)
            case .scroller(let entries, let listing):
                linkCollection(entries)
                more(listing)
            case .mangaList(_, _, let entries, let listing):
                linkCollection(entries)
                more(listing)
            case .mangaChapterList(_, let entries, let listing):
                mangaCollection(entries.map(\.manga))
                more(listing)
            case .links(let links):
                linkCollection(links)
            case .filters(let filters):
                ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
                    Button(filter.title) { Task { await model.searchHomeFilter(filter) } }.disabled(loading)
                }
            }
        }
    }

    @ViewBuilder private func more(_ listing: Listing?) -> some View {
        if let listing {
            Button("查看全部 · " + listing.name) { Task { await model.openListing(listing) } }.disabled(loading)
        }
    }

    private func mangaCollection(_ entries: [AidokuRunner.Manga]) -> some View {
        linkCollection(entries.map { .init(title: $0.title, imageUrl: $0.cover, value: .manga($0)) })
    }

    private func linkCollection(_ entries: [HomeComponent.Value.Link]) -> some View {
        LazyVGrid(columns: model.posterGrid ? [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 12, alignment: .top)] : [GridItem(.flexible())],
                  alignment: .leading, spacing: 16) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, link in
                Button { Task { await model.openHomeLink(link) } } label: {
                    if model.posterGrid {
                        VStack(alignment: .leading, spacing: 6) {
                            cover(link).aspectRatio(2.0 / 3.0, contentMode: .fit)
                            Text(link.title).font(.headline).lineLimit(2).frame(height: 36, alignment: .topLeading)
                            if let subtitle = link.subtitle { Text(subtitle).font(.caption).lineLimit(1).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    } else {
                        HStack(spacing: 10) {
                            cover(link).frame(width: 56, height: 80)
                            VStack(alignment: .leading) {
                                Text(link.title).lineLimit(2)
                                if let subtitle = link.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                }.buttonStyle(.plain).disabled(loading || link.value == nil)
            }
        }
    }

    private func cover(_ link: HomeComponent.Value.Link) -> some View {
        GeometryReader { geometry in
            AsyncImage(url: link.imageUrl.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
