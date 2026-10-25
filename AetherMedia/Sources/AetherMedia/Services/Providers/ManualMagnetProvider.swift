import Foundation

/// Provider supporting manual magnet link insertion, clipboard auto-detection, and .torrent parsing
public final class ManualMagnetProvider: MediaProviderProtocol, Sendable {
    public let id = "builtin.magnet"
    public let displayName = "Manual Magnet Import"
    public let version = "1.0.0"
    public let capabilities: ProviderCapabilities = [.sourceDiscovery, .directPlayback]
    public let isEnabled: Bool = true
    public let priority: Int = 110 // Highest priority when explicitly invoked
    public let supportedTypes: [MediaType] = [.movie, .tvShow, .cloudTorrent, .directStream]
    
    public init() {}
    
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] { [] }
    public func search(query: String) async throws -> [MediaItem] { [] }
    
    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        // If the item ID itself is a magnet or infohash
        if let magnet = SourceStream.normalizedMagnet(item.id) {
            return [parseMagnetLink(magnet, title: item.title)]
        }
        return []
    }
    
    public func parseMagnetLink(_ magnet: String, title: String? = nil) -> SourceStream {
        let detectedHash = SourceStream.extractHash(from: magnet) ?? "MANUAL_MAGNET"
        let displayName = title ?? "Manual Magnet (\(detectedHash.prefix(8)))"
        
        return SourceStream(
            title: displayName,
            providerName: "Manual Magnet Import",
            resolution: VideoResolution.parse(from: displayName),
            sizeBytes: nil,
            seeds: nil,
            isRealDebridCached: false,
            magnetURL: magnet,
            infoHash: detectedHash,
            providerId: id
        )
    }
    
    public func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        guard let magnet = source.magnetURL else {
            throw RealDebridError.debridLinkResolutionFailed("Missing magnet link in manual source.")
        }
        let playable = try await debridClient.resolveMagnetToStream(magnet: magnet, preferredFileIndex: source.fileIndex, preferredFileName: source.originalFileName)
            return playable.withOriginalSource(source)
    }
}
