import Foundation

/// Records playback position and completion for Continue Watching & resumption
public struct UserWatchProgress: Identifiable, Codable, Sendable, Equatable {
    public var id: String { mediaItemId + (episodeId.map { "_\($0)" } ?? "") }
    public let mediaItemId: String
    public let mediaTitle: String
    public let mediaType: MediaType
    public let posterURL: URL?
    public let backdropURL: URL?
    public let episodeId: String?
    public let episodeCode: String?
    public let episodeTitle: String?
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var lastWatchedDate: Date
    public var isCompleted: Bool
    
    public init(
        mediaItemId: String,
        mediaTitle: String,
        mediaType: MediaType,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        episodeId: String? = nil,
        episodeCode: String? = nil,
        episodeTitle: String? = nil,
        positionSeconds: Double,
        durationSeconds: Double,
        lastWatchedDate: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.mediaItemId = mediaItemId
        self.mediaTitle = mediaTitle
        self.mediaType = mediaType
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.episodeId = episodeId
        self.episodeCode = episodeCode
        self.episodeTitle = episodeTitle
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.lastWatchedDate = lastWatchedDate
        self.isCompleted = isCompleted
    }
    
    public var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1.0)
    }
    
    public var shouldResume: Bool {
        // Resume if watched > 15s and less than 92%
        positionSeconds > 15 && progressFraction < 0.92
    }
    
    public var formattedRemainingTime: String {
        guard durationSeconds > positionSeconds else { return "" }
        let remaining = Int(durationSeconds - positionSeconds)
        let mins = (remaining % 3600) / 60
        let hours = remaining / 3600
        if hours > 0 {
            return "\(hours)h \(mins)m left"
        }
        return "\(mins)m left"
    }
}
