import Foundation

/// Episode representation with title, season/episode numbers, still image, and air date
public struct Episode: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let overview: String?
    public let stillURL: URL?
    public let airDate: String?
    public let runtimeMinutes: Int?
    public let rating: Double?
    
    public init(
        id: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        overview: String? = nil,
        stillURL: URL? = nil,
        airDate: String? = nil,
        runtimeMinutes: Int? = nil,
        rating: Double? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.stillURL = stillURL
        self.airDate = airDate
        self.runtimeMinutes = runtimeMinutes
        self.rating = rating
    }
    
    public var code: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }
}
