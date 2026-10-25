import SwiftUI

/// Main Home View featuring Continue Watching carousel, Trending Movies, and TV Shows
@MainActor
public struct HomeView: View {
    @State private var continueWatching: [UserWatchProgress] = []
    @State private var trendingMovies: [MediaItem] = []
    @State private var popularShows: [MediaItem] = []
    @State private var cloudTorrents: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    @State private var loadError: String?
    
    private let providerManager: ProviderManager
    private let persistence: PersistenceServiceProtocol
    
    public init(
        providerManager: ProviderManager = .shared,
        persistence: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.providerManager = providerManager
        self.persistence = persistence
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    NavigationLink(destination: RedLightBrowserView()) {
                        Label("Red Light · Movies & TV", systemImage: "play.rectangle.fill")
                            .font(.headline).foregroundStyle(.red).padding(.horizontal, 16)
                    }
                    
                    if let loadError {
                        ErrorStateBanner(message: loadError) { Task { await loadHomeData() } }
                            .padding(.horizontal, 16)
                    }
                    if isLoading { ProgressView("Loading library…").frame(maxWidth: .infinity) }

                    // MARK: - Continue Watching
                    if !continueWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(title: "Continue Watching", icon: "play.circle.fill")
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(continueWatching) { progress in
                                        ArtworkCard(
                                            item: MediaItem(
                                                id: progress.mediaItemId,
                                                title: progress.mediaTitle,
                                                posterURL: progress.posterURL,
                                                backdropURL: progress.backdropURL,
                                                type: progress.mediaType
                                            ),
                                            mode: .backdrop,
                                            progress: progress.progressFraction,
                                            subtitle: progress.episodeCode ?? progress.formattedRemainingTime
                                        ) {
                                            selectedItem = MediaItem(
                                                id: progress.mediaItemId,
                                                title: progress.mediaTitle,
                                                posterURL: progress.posterURL,
                                                backdropURL: progress.backdropURL,
                                                type: progress.mediaType
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    
                    // MARK: - Trending Movies
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Popular Movies", icon: "flame.fill")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(trendingMovies) { movie in
                                    ArtworkCard(item: movie, mode: .poster) {
                                        selectedItem = movie
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // MARK: - Popular TV Shows
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Popular TV Shows", icon: "tv.fill")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(popularShows) { show in
                                    ArtworkCard(item: show, mode: .poster) {
                                        selectedItem = show
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // MARK: - Real-Debrid Cloud Fast-Access
                    if !cloudTorrents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(title: "Real-Debrid Cloud", icon: "icloud.fill")
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(cloudTorrents) { torrent in
                                        ArtworkCard(item: torrent, mode: .backdrop, subtitle: "View cloud files") {
                                            selectedItem = torrent
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 80) // Tab bar clearance
            }
            .navigationTitle("Aether")
            .refreshable {
                await loadHomeData()
            }
            .task {
                await loadHomeData()
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(mediaItem: item)
            }
        }
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Data Loading
    
    private func loadHomeData() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        continueWatching = (await persistence.loadWatchProgress()).filter { $0.shouldResume }
        do { trendingMovies = try await providerManager.fetchCatalog(category: .popularMovies) }
        catch { if !Task.isCancelled { loadError = error.localizedDescription } }
        guard !Task.isCancelled else { return }
        do { popularShows = try await providerManager.fetchCatalog(category: .popularShows) }
        catch { if !Task.isCancelled { loadError = error.localizedDescription } }
        guard !Task.isCancelled else { return }
        do { cloudTorrents = try await providerManager.fetchCatalog(category: .debridCloud) }
        catch { if !Task.isCancelled { loadError = error.localizedDescription } }
    }
}
