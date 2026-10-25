import Foundation

/// Core media representation displayed in grids, carousels, and search results
public struct MediaItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let overview: String
    public let posterURL: URL?
    public let backdropURL: URL?
    public let releaseYear: Int?
    public let rating: Double?
    public let type: MediaType
    public let imdbId: String?
    public let tmdbId: Int?
    public let providerId: String?
    
    public init(
        id: String,
        title: String,
        overview: String = "",
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        releaseYear: Int? = nil,
        rating: Double? = nil,
        type: MediaType = .movie,
        imdbId: String? = nil,
        tmdbId: Int? = nil,
        providerId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.releaseYear = releaseYear
        self.rating = rating
        self.type = type
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.providerId = providerId
    }
    
    public var formattedRating: String {
        guard let rating = rating, rating > 0 else { return "N/A" }
        return String(format: "%.1f", rating)
    }
    
    public var formattedYear: String {
        guard let releaseYear = releaseYear else { return "" }
        return "\(releaseYear)"
    }
}
