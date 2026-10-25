import Foundation

/// Supported media categories in AetherMedia
public enum MediaType: String, Codable, Sendable, CaseIterable {
    case movie = "Movie"
    case tvShow = "TV Show"
    case anime = "Anime"
    case cloudTorrent = "Cloud Torrent"
    case directStream = "Direct Stream"
    
    public var iconName: String {
        switch self {
        case .movie: return "film"
        case .tvShow: return "tv"
        case .anime: return "sparkles.tv"
        case .cloudTorrent: return "icloud.and.arrow.down"
        case .directStream: return "play.circle"
        }
    }
}

/// Catalog browsing categories for Home and Search feeds
public enum CatalogCategory: String, Codable, Sendable, CaseIterable {
    case trending = "Trending"
    case popularMovies = "Popular Movies"
    case popularShows = "Popular Shows"
    case topRated = "Top Rated"
    case debridCloud = "Real-Debrid Cloud"
    case watchlist = "Watchlist"
    case continueWatching = "Continue Watching"
}
