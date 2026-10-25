import Foundation

/// Protocol defining local persistence capabilities
public protocol PersistenceServiceProtocol: Sendable {
    func loadWatchlist() async -> [MediaItem]
    func saveWatchlist(_ items: [MediaItem]) async
    func addToWatchlist(_ item: MediaItem) async
    func removeFromWatchlist(id: String) async
    func isInWatchlist(id: String) async -> Bool
    
    func loadFavorites() async -> [MediaItem]
    func saveFavorites(_ items: [MediaItem]) async
    func toggleFavorite(_ item: MediaItem) async
    func isFavorite(id: String) async -> Bool
    
    func loadWatchProgress() async -> [UserWatchProgress]
    func saveProgress(_ progress: UserWatchProgress) async
    func getProgress(mediaItemId: String, episodeId: String?) async -> UserWatchProgress?
    func clearProgress(id: String) async
    
    func loadSearchHistory() async -> [String]
    func addSearchQuery(_ query: String) async
    func clearSearchHistory() async
}

/// Actor-based persistence manager ensuring race-free local storage
public actor PersistenceService: PersistenceServiceProtocol {
    public static let shared = PersistenceService()
    
    private let fileManager = FileManager.default
    private let storageDirectory: URL
    
    private var cachedWatchlist: [MediaItem]?
    private var cachedFavorites: [MediaItem]?
    private var cachedProgress: [UserWatchProgress]?
    private var cachedHistory: [String]?
    
    public init(customStorageDirectory: URL? = nil) {
        if let custom = customStorageDirectory {
            self.storageDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.storageDirectory = appSupport.appendingPathComponent("AetherMedia", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }
    
    private var watchlistURL: URL { storageDirectory.appendingPathComponent("watchlist.json") }
    private var favoritesURL: URL { storageDirectory.appendingPathComponent("favorites.json") }
    private var progressURL: URL { storageDirectory.appendingPathComponent("watch_progress.json") }
    private var historyURL: URL { storageDirectory.appendingPathComponent("search_history.json") }
    
    // MARK: - Watchlist
    
    public func loadWatchlist() -> [MediaItem] {
        if let cached = cachedWatchlist { return cached }
        guard let data = try? Data(contentsOf: watchlistURL),
              let items = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            cachedWatchlist = []
            return []
        }
        cachedWatchlist = items
        return items
    }
    
    public func saveWatchlist(_ items: [MediaItem]) {
        cachedWatchlist = items
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: watchlistURL, options: .atomic)
        }
    }
    
    public func addToWatchlist(_ item: MediaItem) {
        var list = loadWatchlist()
        if !list.contains(where: { $0.id == item.id }) {
            list.insert(item, at: 0)
            saveWatchlist(list)
        }
    }
    
    public func removeFromWatchlist(id: String) {
        var list = loadWatchlist()
        list.removeAll { $0.id == id }
        saveWatchlist(list)
    }
    
    public func isInWatchlist(id: String) -> Bool {
        loadWatchlist().contains { $0.id == id }
    }
    
    // MARK: - Favorites
    
    public func loadFavorites() -> [MediaItem] {
        if let cached = cachedFavorites { return cached }
        guard let data = try? Data(contentsOf: favoritesURL),
              let items = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            cachedFavorites = []
            return []
        }
        cachedFavorites = items
        return items
    }
    
    public func saveFavorites(_ items: [MediaItem]) {
        cachedFavorites = items
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: favoritesURL, options: .atomic)
        }
    }
    
    public func toggleFavorite(_ item: MediaItem) {
        var list = loadFavorites()
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list.remove(at: index)
        } else {
            list.insert(item, at: 0)
        }
        saveFavorites(list)
    }
    
    public func isFavorite(id: String) -> Bool {
        loadFavorites().contains { $0.id == id }
    }
    
    // MARK: - Watch Progress
    
    public func loadWatchProgress() -> [UserWatchProgress] {
        if let cached = cachedProgress { return cached }
        guard let data = try? Data(contentsOf: progressURL),
              let items = try? JSONDecoder().decode([UserWatchProgress].self, from: data) else {
            cachedProgress = []
            return []
        }
        cachedProgress = items
        return items
    }
    
    public func saveProgress(_ progress: UserWatchProgress) {
        var items = loadWatchProgress()
        if let index = items.firstIndex(where: { $0.id == progress.id }) {
            items[index] = progress
        } else {
            items.insert(progress, at: 0)
        }
        items.sort { $0.lastWatchedDate > $1.lastWatchedDate }
        // Keep most recent 50 entries
        if items.count > 50 {
            items = Array(items.prefix(50))
        }
        cachedProgress = items
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: progressURL, options: .atomic)
        }
    }
    
    public func getProgress(mediaItemId: String, episodeId: String?) -> UserWatchProgress? {
        let targetId = mediaItemId + (episodeId.map { "_\($0)" } ?? "")
        return loadWatchProgress().first { $0.id == targetId }
    }
    
    public func clearProgress(id: String) {
        var items = loadWatchProgress()
        items.removeAll { $0.id == id }
        cachedProgress = items
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: progressURL, options: .atomic)
        }
    }
    
    // MARK: - Search History
    
    public func loadSearchHistory() -> [String] {
        if let cached = cachedHistory { return cached }
        guard let data = try? Data(contentsOf: historyURL),
              let items = try? JSONDecoder().decode([String].self, from: data) else {
            cachedHistory = []
            return []
        }
        cachedHistory = items
        return items
    }
    
    public func addSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = loadSearchHistory()
        history.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        history.insert(trimmed, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        cachedHistory = history
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
    
    public func clearSearchHistory() {
        cachedHistory = []
        if let data = try? JSONEncoder().encode([String]()) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
