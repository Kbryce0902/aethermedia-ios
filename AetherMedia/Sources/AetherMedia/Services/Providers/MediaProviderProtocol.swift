import Foundation

/// Capabilities supported by a media provider
public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    
    public static let catalogBrowsing = ProviderCapabilities(rawValue: 1 << 0)
    public static let search          = ProviderCapabilities(rawValue: 1 << 1)
    public static let sourceDiscovery = ProviderCapabilities(rawValue: 1 << 2)
    public static let directPlayback  = ProviderCapabilities(rawValue: 1 << 3)
    
    public static let all: ProviderCapabilities = [.catalogBrowsing, .search, .sourceDiscovery, .directPlayback]
}

/// Common protocol that all source, catalog, and debrid providers implement
public protocol MediaProviderProtocol: Sendable {
    var id: String { get }
    var displayName: String { get }
    var version: String { get }
    var capabilities: ProviderCapabilities { get }
    var isEnabled: Bool { get }
    var priority: Int { get }
    var supportedTypes: [MediaType] { get }
    
    /// Search the provider for media matching a user query
    func search(query: String) async throws -> [MediaItem]
    
    /// Fetch catalog items for a given feed category
    func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem]
    
    /// Discover available source streams for a movie or TV episode
    func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream]
    
    /// Resolve a selected source stream into a direct playable stream via Real-Debrid
    func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream
}
