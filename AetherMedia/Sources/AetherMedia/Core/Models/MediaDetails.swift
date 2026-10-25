import Foundation

/// Detailed metadata for Movies or TV Shows
public struct MediaDetails: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let originalTitle: String?
    public let tagline: String?
    public let overview: String
    public let posterURL: URL?
    public let backdropURL: URL?
    public let releaseDate: String?
    public let releaseYear: Int?
    public let runtimeMinutes: Int?
    public let rating: Double?
    public let voteCount: Int?
    public let genres: [String]
    public let type: MediaType
    public let imdbId: String?
    public let tmdbId: Int?
    public let status: String?
    public let seasons: [Season]
    public let cast: [CastMember]
    
    public init(
        id: String,
        title: String,
        originalTitle: String? = nil,
        tagline: String? = nil,
        overview: String = "",
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        releaseDate: String? = nil,
        releaseYear: Int? = nil,
        runtimeMinutes: Int? = nil,
        rating: Double? = nil,
        voteCount: Int? = nil,
        genres: [String] = [],
        type: MediaType = .movie,
        imdbId: String? = nil,
        tmdbId: Int? = nil,
        status: String? = nil,
        seasons: [Season] = [],
        cast: [CastMember] = []
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.tagline = tagline
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.releaseDate = releaseDate
        self.releaseYear = releaseYear
        self.runtimeMinutes = runtimeMinutes
        self.rating = rating
        self.voteCount = voteCount
        self.genres = genres
        self.type = type
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.status = status
        self.seasons = seasons
        self.cast = cast
    }
    
    public var formattedRuntime: String {
        guard let minutes = runtimeMinutes, minutes > 0 else { return "" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
    
    public var asMediaItem: MediaItem {
        MediaItem(
            id: id,
            title: title,
            overview: overview,
            posterURL: posterURL,
            backdropURL: backdropURL,
            releaseYear: releaseYear,
            rating: rating,
            type: type,
            imdbId: imdbId,
            tmdbId: tmdbId
        )
    }
}

/// TV Show Season representation
public struct Season: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let seasonNumber: Int
    public let name: String
    public let overview: String?
    public let posterURL: URL?
    public let episodeCount: Int
    public var episodes: [Episode]
    
    public init(
        id: String,
        seasonNumber: Int,
        name: String,
        overview: String? = nil,
        posterURL: URL? = nil,
        episodeCount: Int = 0,
        episodes: [Episode] = []
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.posterURL = posterURL
        self.episodeCount = episodeCount
        self.episodes = episodes
    }
}

/// Cast member representation
public struct CastMember: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let character: String?
    public let profileURL: URL?
    
    public init(id: String, name: String, character: String? = nil, profileURL: URL? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.profileURL = profileURL
    }
}
