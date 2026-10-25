import SwiftUI

/// A dedicated entry point keeps Red Light's source search separate from the combined provider.
@MainActor
struct RedLightBrowserView: View {
    @State private var movies: [MediaItem] = []
    @State private var shows: [MediaItem] = []
    @State private var results: [MediaItem] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var selected: MediaItem?
    private let metadata = StremioMetadataClient.shared
    private let sourceManager = ProviderManager(providers: [RedLightNativeProvider()], preferences: nil)
    var body: some View {
        List {
            Section {
                NavigationLink("Source Services & AIOStreams", destination: RedLightSettingsView())
                Text("Browse a title, choose an episode, then search Red Light's enabled services. Catalogue and artwork are supplied by Cinemeta.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading…") }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.orange); Button("Retry") { Task { await load() } } }
            }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleSection("Movies", items: movies)
                titleSection("TV Shows", items: shows)
            } else { titleSection("Search Results", items: results) }
        }
        .navigationTitle("Red Light")
        .searchable(text: $query, prompt: "Search movies and TV")
        .task(id: query) {
            if query.isEmpty { await load() }
            else {
                do { try await Task.sleep(nanoseconds: 400_000_000); await load() } catch {}
            }
        }
        .navigationDestination(item: $selected) { item in
            MediaDetailView(mediaItem: item, providerManager: sourceManager)
        }
    }
    private func titleSection(_ title: String, items: [MediaItem]) -> some View {
        Section(title) {
            ForEach(items) { item in
                Button { selected = item } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: item.posterURL) { image in image.resizable().scaledToFill() }
                        placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 45, height: 65).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading) {
                            Text(item.title).foregroundStyle(.primary)
                            Text("\(item.type == .movie ? "Movie" : "TV Show") · \(item.formattedYear)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if search.isEmpty {
                async let m = metadata.catalog(category: .popularMovies)
                async let s = metadata.catalog(category: .popularShows)
                let pair = try await (m, s)
                try Task.checkCancellation(); movies = pair.0; shows = pair.1
            } else {
                let items = try await metadata.search(query: search)
                try Task.checkCancellation(); results = items
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
