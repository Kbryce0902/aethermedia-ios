import Foundation

public struct SourceDiscoveryResult: Sendable {
    public let sources: [SourceStream]
    public let warnings: [String]
    public let reports: [SourceBackendReport]
    public init(sources: [SourceStream], warnings: [String] = [], reports: [SourceBackendReport] = []) {
        self.sources = sources; self.warnings = warnings; self.reports = reports
    }
}

public struct SourceBackendReport: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let received: Int
    public let accepted: Int
    public let message: String?
    public init(id: String, name: String, status: String, received: Int = 0, accepted: Int = 0, message: String? = nil) {
        self.id = id; self.name = name; self.status = status; self.received = received; self.accepted = accepted; self.message = message
    }
}

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
    func discoverSourceResult(for item: MediaItem, episode: Episode?) async throws -> SourceDiscoveryResult
    
    /// Resolve a selected source stream into a direct playable stream via Real-Debrid
    func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream
}

public extension MediaProviderProtocol {
    func discoverSourceResult(for item: MediaItem, episode: Episode?) async throws -> SourceDiscoveryResult {
        SourceDiscoveryResult(sources: try await discoverSources(for: item, episode: episode))
    }
}
