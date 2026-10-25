import SwiftUI

/// User Library managing Watchlist, Favorites, and direct Real-Debrid Cloud Torrents
@MainActor
public struct LibraryView: View {
    public enum LibraryTab: String, CaseIterable {
        case watchlist = "Watchlist"
        case favorites = "Favorites"
        case rdCloud = "Debrid Cloud"
    }
    
    @State private var selectedTab: LibraryTab = .watchlist
    @State private var watchlistItems: [MediaItem] = []
    @State private var favoriteItems: [MediaItem] = []
    @State private var cloudTorrents: [RDTorrent] = []
    @State private var isLoadingCloud = false
    @State private var showingMagnetSheet = false
    @State private var selectedMediaItem: MediaItem?
    @State private var pendingImportedItem: MediaItem?
    @State private var cloudError: String?
    @State private var cloudErrorDetails: String?
    @State private var cloudWarning: String?
    @State private var cloudWarningDetails: String?
    
    private let persistence: PersistenceServiceProtocol
    private let debridClient: RealDebridClientProtocol
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)
    ]
    
    public init(
        persistence: PersistenceServiceProtocol = PersistenceService.shared,
        debridClient: RealDebridClientProtocol = RealDebridClient.shared
    ) {
        self.persistence = persistence
        self.debridClient = debridClient
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Segmented Tab Picker
                Picker("Library Section", selection: $selectedTab) {
                    ForEach(LibraryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // Tab Content
                switch selectedTab {
                case .watchlist:
                    watchlistContent
                case .favorites:
                    favoritesContent
                case .rdCloud:
                    rdCloudContent
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingMagnetSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .sheet(isPresented: $showingMagnetSheet, onDismiss: {
                if let item = pendingImportedItem { selectedMediaItem = item; pendingImportedItem = nil }
            }) {
                MagnetImportSheet { magnet in
                    let id = try await debridClient.addMagnet(magnet)
                    try Task.checkCancellation()
                    pendingImportedItem = MediaItem(id: "rd_cloud_\(id)", title: "Imported Magnet", type: .cloudTorrent, providerId: "builtin.debrid.cloud")
                    selectedTab = .rdCloud
                    await loadCloudTorrents()
                }
            }
            .task {
                await reloadData()
            }
            .refreshable {
                await reloadData()
            }
            .navigationDestination(item: $selectedMediaItem) { item in
                MediaDetailView(mediaItem: item)
            }

        }
    }
    
    // MARK: - Watchlist Tab
    
    private var watchlistContent: some View {
        Group {
            if watchlistItems.isEmpty {
                EmptyStateCard(
                    icon: "bookmark",
                    title: "Watchlist is Empty",
                    message: "Save movies and TV shows from details to watch them later."
                )
                .padding(.top, 40)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(watchlistItems) { item in
                            ArtworkCard(item: item, mode: .poster) {
                                selectedMediaItem = item
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }
            }
        }
    }
    
    // MARK: - Favorites Tab
    
    private var favoritesContent: some View {
        Group {
            if favoriteItems.isEmpty {
                EmptyStateCard(
                    icon: "heart",
                    title: "No Favorites Yet",
                    message: "Heart your all-time favorite content for quick access."
                )
                .padding(.top, 40)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(favoriteItems) { item in
                            ArtworkCard(item: item, mode: .poster) {
                                selectedMediaItem = item
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }
            }
        }
    }
    
    // MARK: - Real-Debrid Cloud Tab
    
    private var rdCloudContent: some View {
        Group {
            if !debridClient.isAuthenticated {
                EmptyStateCard(icon: "person.crop.circle.badge.exclamationmark", title: "Real-Debrid Disconnected",
                    message: "Connect your Real-Debrid account in Settings to view and stream your cloud files.")
                Spacer()
            } else {
                VStack(spacing: 10) {
                    if let cloudError {
                        ErrorStateBanner(message: cloudError, details: cloudErrorDetails) { Task { await loadCloudTorrents() } }
                    }
                    if let cloudWarning {
                        ErrorStateBanner(message: cloudWarning, details: cloudWarningDetails) { Task { await loadCloudTorrents() } }
                    }
                    if isLoadingCloud && cloudTorrents.isEmpty {
                        Spacer(); ProgressView("Syncing Real-Debrid Cloud..."); Spacer()
                    } else if cloudTorrents.isEmpty {
                        if cloudError == nil && cloudWarning == nil {
                            EmptyStateCard(icon: "icloud.and.arrow.down", title: "Cloud Storage Empty",
                                message: "Add torrents using the + button above or discover them in Search.",
                                actionTitle: "Import Magnet Link", action: { showingMagnetSheet = true })
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(cloudTorrents) { torrent in torrentRow(torrent) }
                                .onDelete(perform: deleteTorrent)
                        }.listStyle(PlainListStyle())
                    }
                }
            }
        }
    }

    // MARK: - Torrent Row
    
    private func torrentRow(_ torrent: RDTorrent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: torrent.isReadyToStream ? "play.circle.fill" : "arrow.down.circle")
                .font(.title2)
                .foregroundColor(torrent.isReadyToStream ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(torrent.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(torrent.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(torrent.status.capitalized)
                        .font(.caption2.bold())
                        .foregroundColor(torrent.isReadyToStream ? .green : .orange)
                    
                    if torrent.progress < 100 && torrent.progress > 0 {
                        Text("(\(Int(torrent.progress))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if torrent.isReadyToStream {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMediaItem = MediaItem(id: "rd_cloud_\(torrent.id)", title: torrent.filename,
                        overview: "Status: \(torrent.status)", type: .cloudTorrent, providerId: "builtin.debrid.cloud")
        }
    }
    
    // MARK: - Actions
    
    private func reloadData() async {
        watchlistItems = await persistence.loadWatchlist()
        favoriteItems = await persistence.loadFavorites()
        if debridClient.isAuthenticated {
            await loadCloudTorrents()
        }
    }
    
    private func loadCloudTorrents() async {
        isLoadingCloud = true
        cloudError = nil
        cloudErrorDetails = nil
        cloudWarning = nil
        cloudWarningDetails = nil
        defer { isLoadingCloud = false }
        do {
            let page = try await debridClient.getTorrentPage(offset: 0, limit: 2500)
            try Task.checkCancellation()
            cloudTorrents = page.items
            cloudWarning = page.warningMessage
            cloudWarningDetails = page.firstFailure?.diagnosticDetails
        } catch {
            if !Task.isCancelled {
                cloudError = error.localizedDescription
                cloudErrorDetails = (error as? RealDebridError)?.diagnosticDetails
            }
        }
    }
    
    private func deleteTorrent(at offsets: IndexSet) {
        let targets = offsets.compactMap { cloudTorrents.indices.contains($0) ? cloudTorrents[$0] : nil }
        Task {
            do {
                for torrent in targets { try await debridClient.deleteTorrent(id: torrent.id) }
                await loadCloudTorrents()
            } catch { if !Task.isCancelled { cloudError = error.localizedDescription } }
        }
    }
}
