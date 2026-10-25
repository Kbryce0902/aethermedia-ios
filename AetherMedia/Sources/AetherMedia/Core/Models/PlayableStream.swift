import Foundation

/// Subtitle track descriptor
public struct SubtitleTrack: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let language: String
    public let label: String
    public let url: URL
    public let isDefault: Bool
    
    public init(id: String = UUID().uuidString, language: String, label: String, url: URL, isDefault: Bool = false) {
        self.id = id
        self.language = language
        self.label = label
        self.url = url
        self.isDefault = isDefault
    }
}

/// Fully resolved playable stream ready for AVFoundation / AVPlayer
public struct PlayableStream: Identifiable, Sendable {
    public let id: String
    public let streamURL: URL
    public let title: String
    public let filename: String
    public let mimeType: String?
    public let fileSize: Int64?
    public let subtitles: [SubtitleTrack]
    public let expiresAt: Date?
    public let originalSource: SourceStream?
    
    public init(
        id: String = UUID().uuidString,
        streamURL: URL,
        title: String,
        filename: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        subtitles: [SubtitleTrack] = [],
        expiresAt: Date? = nil,
        originalSource: SourceStream? = nil
    ) {
        self.id = id
        self.streamURL = streamURL
        self.title = title
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.subtitles = subtitles
        self.expiresAt = expiresAt
        self.originalSource = originalSource
    }
    
    public func withOriginalSource(_ source: SourceStream) -> PlayableStream {
        PlayableStream(id: id, streamURL: streamURL, title: title, filename: filename, mimeType: mimeType,
                       fileSize: fileSize, subtitles: subtitles, expiresAt: expiresAt, originalSource: source)
    }

    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}
