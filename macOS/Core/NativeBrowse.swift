import AppKit
import AidokuRunner

extension MacModel {
    func loadBrowseHome() async {
        let token = UUID()
        browseGeneration = token
        guard let source = sources.first(where: { $0.key == sourceKey }) else {
            home = nil; listings = []; results = []; hasNextResults = false
            return
        }
        browseLoading = true
        browseError = nil
        home = nil; results = []; hasNextResults = false; selectedListing = nil; browseFilters = nil
        loadedBrowseSource = source.key
        browseTitle = "首页"
        defer { if browseGeneration == token { browseLoading = false } }
        do {
            let available = try await source.getListings()
            guard browseGeneration == token else { return }
            listings = available
            if source.features.providesHome {
                let loaded = try await source.getHome()
                guard browseGeneration == token else { return }
                home = loaded
            } else if let first = available.first {
                await openListing(first)
            } else {
                await search()
            }
        } catch {
            if browseGeneration == token { browseError = error.localizedDescription }
        }
    }

    func openListing(_ listing: AidokuRunner.Listing, next: Bool = false) async {
        guard let source = sources.first(where: { $0.key == sourceKey }) else { return }
        let append = next && selectedListing == listing
        let requestedPage = append ? browsePage + 1 : 1
        let token = UUID()
        browseGeneration = token
        browseLoading = true
        browseError = nil
        home = nil
        if !append { results = []; hasNextResults = false }
        browseFilters = nil
        selectedListing = listing
        browseTitle = listing.name
        defer { if browseGeneration == token { browseLoading = false } }
        do {
            let loaded = try await source.getMangaList(listing: listing, page: requestedPage)
            guard browseGeneration == token, sourceKey == source.key else { return }
            var seen = Set<String>()
            results = (append ? results + loaded.entries : loaded.entries).filter { seen.insert($0.key).inserted }
            hasNextResults = loaded.hasNextPage
            browsePage = requestedPage
        } catch {
            if browseGeneration == token { browseError = error.localizedDescription }
        }
    }

    func openHomeLink(_ link: HomeComponent.Value.Link) async {
        switch link.value {
        case .manga(let item): await selectManga(item, sourceKey: sourceKey)
        case .listing(let listing): await openListing(listing)
        case .url(let value):
            if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        case nil: break
        }
    }

    func searchHomeFilter(_ filter: HomeComponent.Value.FilterItem) async {
        guard let source = sources.first(where: { $0.key == sourceKey }) else { return }
        let token = UUID()
        browseGeneration = token
        browseLoading = true; browseError = nil
        home = nil; selectedListing = nil; results = []; hasNextResults = false
        browseTitle = filter.title
        defer { if browseGeneration == token { browseLoading = false } }
        do {
            let loaded = try await source.getSearchMangaList(query: nil, page: 1, filters: filter.values ?? [])
            guard browseGeneration == token else { return }
            results = loaded.entries
            // Filters retain their own pagination context.
            browseFilters = filter.values ?? []
            browsePage = 1
            hasNextResults = loaded.hasNextPage
        } catch {
            if browseGeneration == token { browseError = error.localizedDescription }
        }
    }

    func loadMoreBrowse() async {
        if let listing = selectedListing { await openListing(listing, next: true) }
        else if let filters = browseFilters {
            guard !browseLoading, let source = sources.first(where: { $0.key == sourceKey }) else { return }
            let token = browseGeneration
            browseLoading = true
            defer { if browseGeneration == token { browseLoading = false } }
            do {
                let loaded = try await source.getSearchMangaList(query: nil, page: browsePage + 1, filters: filters)
                guard browseGeneration == token else { return }
                var seen = Set(results.map(\.key))
                results += loaded.entries.filter { seen.insert($0.key).inserted }
                browsePage += 1
                hasNextResults = loaded.hasNextPage
            } catch { if browseGeneration == token { browseError = error.localizedDescription } }
        } else { await search(next: true) }
    }
}
