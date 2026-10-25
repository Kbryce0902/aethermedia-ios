import Foundation

public struct RedLightNativeProvider: MediaProviderProtocol {
    public let id = "native.redlight"
    public let displayName = "Red Light"
    public let version = "0.3.6"
    public let capabilities: ProviderCapabilities = [.sourceDiscovery, .directPlayback]
    public let isEnabled = true, priority = 99
    public let supportedTypes: [MediaType] = [.movie, .tvShow, .anime]
    private let client: RedLightSourceClient
    public init(client: RedLightSourceClient = RedLightSourceClient()) { self.client = client }
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] { [] }
    public func search(query: String) async throws -> [MediaItem] { [] }
    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        try await discoverSourceResult(for: item, episode: episode).sources
    }
    public func discoverSourceResult(for item: MediaItem, episode: Episode?) async throws -> SourceDiscoveryResult {
        try await client.discover(for: item, episode: episode)
    }
    public func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        if let magnet = source.magnetURL {
            return try await debridClient.resolveMagnetToStream(magnet: magnet, preferredFileIndex: source.fileIndex,
                preferredFileName: source.originalFileName, season: source.targetSeason, episode: source.targetEpisode).withOriginalSource(source)
        }
        if let url = source.directURL, url.scheme?.lowercased() == "https", url.host != nil {
            return PlayableStream(streamURL: url, title: source.title, filename: source.originalFileName ?? url.lastPathComponent, originalSource: source)
        }
        throw ProviderServiceError.unavailable("Red Light returned no supported torrent or HTTPS stream.")
    }
}
