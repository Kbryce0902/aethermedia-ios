import SwiftUI

/// Search screen with debounced queries, category filters, history chips, and results grid
@MainActor
public struct SearchView: View {
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var searchHistory: [String] = []
    @State private var isSearching = false
    @State private var selectedItem: MediaItem?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = UUID()
    
    private let providerManager: ProviderManager
    private let persistence: PersistenceServiceProtocol
    
    public init(
        providerManager: ProviderManager = .shared,
        persistence: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.providerManager = providerManager
        self.persistence = persistence
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)
    ]
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Search Input Field with Glass Styling
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search movies, shows, or paste magnet...", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !query.isEmpty {
                        Button(action: {
                            query = ""
                            results = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liquidGlass(style: .card, cornerRadius: 16)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 16)
                }

                // Content Body
                if isSearching {
                    Spacer()
                    ProgressView("Searching providers...")
                    Spacer()
                } else if !results.isEmpty {
                    resultsGrid
                } else if !searchHistory.isEmpty && query.isEmpty {
                    searchHistorySection
                } else if !query.isEmpty {
                    EmptyStateCard(
                        icon: "magnifyingglass",
                        title: "No Results Found",
                        message: "We couldn't find matches for '\(query)'."
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    EmptyStateCard(
                        icon: "film.stack",
                        title: "Discover Media",
                        message: "Search across all enabled providers, cached Real-Debrid streams, and your cloud library."
                    )
                    .padding(.top, 40)
                    Spacer()
                }
            }
            .navigationTitle("Search")
            .onChange(of: query) { _, _ in performSearch(debounce: true) }
            .onDisappear { searchTask?.cancel(); isSearching = false }
            .task {
                searchHistory = await persistence.loadSearchHistory()
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(mediaItem: item)
            }
        }
    }
    
    // MARK: - Results Grid
    
    private var resultsGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(results) { item in
                    ArtworkCard(item: item, mode: .poster) {
                        selectedItem = item
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
    }
    
    // MARK: - Search History
    
    private var searchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Searches")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button("Clear") {
                    Task {
                        await persistence.clearSearchHistory()
                        searchHistory = []
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(searchHistory, id: \.self) { term in
                        Button(action: {
                            query = term
                            performSearch()
                        }) {
                            Text(term)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .liquidGlass(style: .floatingPill, cornerRadius: 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Spacer()
        }
        .padding(.top, 16)
    }
    
    // MARK: - Search Execution
    
    private func performSearch(debounce: Bool = false) {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard !trimmed.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            do {
                if debounce { try await Task.sleep(nanoseconds: 350_000_000) }
                let found = try await providerManager.search(query: trimmed)
                try Task.checkCancellation()
                guard generation == searchGeneration else { return }
                results = found
                if !debounce && SourceStream.normalizedMagnet(trimmed) == nil {
                    await persistence.addSearchQuery(trimmed)
                    searchHistory = await persistence.loadSearchHistory()
                }
                isSearching = false
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = []
                errorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }
}
