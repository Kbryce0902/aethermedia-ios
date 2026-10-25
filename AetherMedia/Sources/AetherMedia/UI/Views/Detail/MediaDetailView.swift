import SwiftUI
import UIKit

/// Media Details screen displaying artwork, synopsis, seasons/episodes, and source selection
@MainActor
public struct MediaDetailView: View {
    public let mediaItem: MediaItem
    
    @State private var details: MediaDetails?
    @State private var selectedSeason: Season?
    @State private var selectedEpisode: Episode?
    @State private var isInWatchlist = false
    @State private var isFavorite = false
    @State private var watchProgress: UserWatchProgress?
    @State private var showingSourceSheet = false
    @State private var pendingStream: PlayableStream?
    @State private var detailsError: String?
    @State private var activeStream: PlayableStream?
    
    private let providerManager: ProviderManager
    private let persistence: PersistenceServiceProtocol
    
    public init(
        mediaItem: MediaItem,
        providerManager: ProviderManager = .shared,
        persistence: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.mediaItem = mediaItem
        self.providerManager = providerManager
        self.persistence = persistence
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                
                // MARK: - Hero Backdrop
                ZStack(alignment: .bottomLeading) {
                    backdropImage
                        .frame(height: 260)
                        .clipped()
                    
                    LinearGradient(
                        colors: [.clear, Color(UIColor.systemBackground).opacity(0.8), Color(UIColor.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mediaItem.title)
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        metadataRow
                    }
                    .padding(.horizontal, 16)
                }
                
                // MARK: - Action Buttons
                HStack(spacing: 12) {
                    GlassButton(
                        title: playButtonTitle,
                        systemImage: "play.fill",
                        variant: .prominentPlay
                    ) {
                        showingSourceSheet = true
                    }
                    .disabled((mediaItem.type == .tvShow || mediaItem.type == .anime) && selectedEpisode == nil)
                    
                    GlassButton(
                        systemImage: isInWatchlist ? "bookmark.fill" : "bookmark",
                        variant: .iconOnly
                    ) {
                        toggleWatchlist()
                    }
                    
                    GlassButton(
                        systemImage: isFavorite ? "heart.fill" : "heart",
                        variant: .iconOnly
                    ) {
                        toggleFavorite()
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                
                // MARK: - Synopsis
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text((details?.overview ?? mediaItem.overview).isEmpty ? "No overview available." : (details?.overview ?? mediaItem.overview))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                if let detailsError {
                    ErrorStateBanner(message: detailsError) { Task { await loadDetails() } }
                        .padding(.horizontal, 16)
                }

                // MARK: - TV Show Episodes (if TV Show)
                if mediaItem.type == .tvShow || mediaItem.type == .anime, let details = details, !details.seasons.isEmpty {
                    episodesSection(seasons: details.seasons)
                }
            }
            .padding(.bottom, 60)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetails()
        }
        .sheet(isPresented: $showingSourceSheet, onDismiss: {
            if let stream = pendingStream { activeStream = stream; pendingStream = nil }
        }) {
            SourceSelectionSheet(mediaItem: mediaItem, episode: selectedEpisode, providerManager: providerManager) { stream in
                pendingStream = stream
                showingSourceSheet = false
            }
        }
        .fullScreenCover(item: $activeStream, onDismiss: { Task { await updateProgress() } }) { stream in
            PlayerView(stream: stream, mediaItem: mediaItem, episode: selectedEpisode,
                       resumeSeconds: watchProgress?.shouldResume == true ? watchProgress?.positionSeconds : nil)
        }
    }
    

    // MARK: - Backdrop Image
    
    private var backdropImage: some View {
        ZStack {
            if let url = mediaItem.backdropURL ?? mediaItem.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.secondary.opacity(0.2)
                    }
                }
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }
    
    // MARK: - Metadata Row
    
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let year = mediaItem.releaseYear {
                Text("\(year)")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
            }
            
            Text("•")
                .foregroundColor(.secondary)
            
            Text(mediaItem.type.rawValue)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            if let rating = mediaItem.rating, rating > 0 {
                Text("•")
                    .foregroundColor(.secondary)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(mediaItem.formattedRating)
                        .font(.subheadline.bold())
                }
            }
        }
    }
    
    // MARK: - Episodes Section
    
    private func episodesSection(seasons: [Season]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
            
            // Season Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        Button(action: { selectedSeason = season }) {
                            Text(season.name)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedSeason?.id == season.id ? Color.accentColor : Color.clear)
                                .foregroundColor(selectedSeason?.id == season.id ? .white : .primary)
                                .clipShape(Capsule())
                                .liquidGlass(style: .floatingPill, cornerRadius: 18)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Episodes List
            if let season = selectedSeason ?? seasons.first {
                VStack(spacing: 10) {
                    ForEach(season.episodes) { ep in
                        HStack(spacing: 12) {
                            Text("\(ep.episodeNumber)")
                                .font(.headline.bold())
                                .foregroundColor(.secondary)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if let runtime = ep.runtimeMinutes {
                                    Text("\(runtime)m")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .padding(12)
                        .liquidGlass(style: .card, cornerRadius: 12)
                        .onTapGesture {
                            selectedEpisode = ep
                            Task {
                                await updateProgress()
                                showingSourceSheet = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - State & Actions
    
    private var playButtonTitle: String {
        if let progress = watchProgress, progress.shouldResume {
            return "Resume (\(progress.formattedRemainingTime))"
        }
        return selectedEpisode.map { "Find \($0.code) Streams" } ?? "Find Streams"
    }
    
    private func updateProgress() async {
        watchProgress = await persistence.getProgress(mediaItemId: mediaItem.id, episodeId: selectedEpisode?.id)
    }

    private func loadDetails() async {
        isInWatchlist = await persistence.isInWatchlist(id: mediaItem.id)
        isFavorite = await persistence.isFavorite(id: mediaItem.id)
        detailsError = nil
        if mediaItem.type == .movie || mediaItem.type == .tvShow || mediaItem.type == .anime {
            do {
                details = try await StremioMetadataClient.shared.details(for: mediaItem)
                if mediaItem.type == .tvShow || mediaItem.type == .anime {
                    let progress = (await persistence.loadWatchProgress()).filter { $0.mediaItemId == mediaItem.id && $0.shouldResume }
                        .sorted { $0.lastWatchedDate > $1.lastWatchedDate }.first
                    let seasons = details?.seasons ?? []
                    selectedEpisode = seasons.flatMap(\.episodes).first { $0.id == progress?.episodeId }
                        ?? seasons.first(where: { $0.seasonNumber > 0 })?.episodes.first ?? seasons.first?.episodes.first
                    selectedSeason = seasons.first { $0.seasonNumber == selectedEpisode?.seasonNumber }
                    if selectedEpisode == nil { detailsError = "No episode metadata was returned. Try loading details again." }
                }
            } catch {
                guard !Task.isCancelled else { return }
                detailsError = error.localizedDescription
            }
        }
        await updateProgress()
    }

    private func toggleWatchlist() {
        Task {
            if isInWatchlist {
                await persistence.removeFromWatchlist(id: mediaItem.id)
                isInWatchlist = false
            } else {
                await persistence.addToWatchlist(mediaItem)
                isInWatchlist = true
            }
        }
    }
    
    private func toggleFavorite() {
        Task {
            await persistence.toggleFavorite(mediaItem)
            isFavorite.toggle()
        }
    }
}
