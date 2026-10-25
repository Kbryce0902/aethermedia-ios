import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native HTTP client for the Stremio metadata/stream protocols; no simulated discoveries.
public final class BuiltInTorrentioProvider: MediaProviderProtocol, Sendable {
    public let id = "builtin.torrentio"
    public let displayName = "Cinemeta & Torrentio"
    public let version = "0.2.0"
    public let capabilities: ProviderCapabilities = .all
    public let isEnabled = true
    public let priority = 100
    public let supportedTypes: [MediaType] = [.movie, .tvShow, .anime]
    private let transport: StremioTransport
    private let metadata: StremioMetadataClient
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = URL(string: "https://torrentio.strem.fun")!,
                metadata: StremioMetadataClient? = nil) {
        self.transport = StremioTransport(session: session)
        self.metadata = metadata ?? StremioMetadataClient(session: session)
        self.endpoint = endpoint
    }
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] {
        try await metadata.catalog(category: category)
    }
    public func search(query: String) async throws -> [MediaItem] { try await metadata.search(query: query) }

    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        guard supportedTypes.contains(item.type), let imdb = item.imdbId ?? (item.id.hasPrefix("tt") ? item.id : nil) else { return [] }
        let isSeries = item.type == .tvShow || item.type == .anime
        if isSeries && episode == nil { throw ProviderServiceError.unavailable("Choose an episode before finding streams.") }
        let videoId = episode.map { "\(imdb):\($0.seasonNumber):\($0.episodeNumber)" } ?? imdb
        let path = "/stream/\(isSeries ? "series" : "movie")/\(StremioTransport.escape(videoId)).json"
        let url = URL(string: endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!
        let result = try await transport.get(StreamResponse.self, url: url)
        return result.streams.compactMap { stream in
            let hash = SourceStream.extractHash(from: stream.infoHash)
            let direct = stream.url.flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
            guard hash != nil || direct != nil else { return nil }
            let title = stream.title ?? stream.description ?? stream.name ?? item.title
            return SourceStream(id: "\(id):\(hash ?? direct!.absoluteString):\(stream.fileIdx ?? -1)",
                                title: title, providerName: displayName, sizeBytes: stream.behaviorHints?.videoSize,
                                isRealDebridCached: false, magnetURL: hash.map { "magnet:?xt=urn:btih:\($0)" },
                                infoHash: hash, fileIndex: stream.fileIdx, originalFileName: stream.behaviorHints?.filename,
                                providerId: id, directURL: direct)
        }
    }
    public func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        if let url = source.directURL, url.scheme?.lowercased() == "https", url.host != nil {
            return PlayableStream(streamURL: url, title: source.title, filename: source.originalFileName ?? url.lastPathComponent, originalSource: source)
        }
        if let magnet = source.magnetURL {
            let playable = try await debridClient.resolveMagnetToStream(magnet: magnet, preferredFileIndex: source.fileIndex, preferredFileName: source.originalFileName)
            return playable.withOriginalSource(source)
        }
        throw RealDebridError.debridLinkResolutionFailed("The provider returned no valid HTTPS playback URL or magnet.")
    }
}
private struct StreamResponse: Decodable { let streams: [StreamDTO] }
private struct StreamDTO: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let infoHash: String?
    let fileIdx: Int?
    let url: String?
    let behaviorHints: StreamHints?
}
private struct StreamHints: Decodable { let filename: String?; let videoSize: Int64? }
