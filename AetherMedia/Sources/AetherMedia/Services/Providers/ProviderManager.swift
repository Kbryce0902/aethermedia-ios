import Foundation

public struct ProviderStatus: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String
    public let isEnabled: Bool
    public let isAvailable: Bool
}

/// Registry state is protected by a synchronous lock; network work always occurs outside it.
public final class ProviderManager: @unchecked Sendable {
    public static let shared = ProviderManager()
    private let lock = NSLock()
    private var providers: [any MediaProviderProtocol] = []
    private var disabledIds: Set<String>
    private var sourceWarnings: [String] = []
    private let preferences: UserDefaults?
    private let debridClient: RealDebridClientProtocol

    public init(debridClient: RealDebridClientProtocol = RealDebridClient.shared,
                providers: [any MediaProviderProtocol]? = nil, preferences: UserDefaults? = .standard) {
        self.debridClient = debridClient
        self.preferences = preferences
        disabledIds = Set(preferences?.stringArray(forKey: "disabledProviderIds") ?? [])
        self.providers = providers ?? [BuiltInTorrentioProvider(), SerenNativeProvider(), RedLightNativeProvider(), ManualMagnetProvider(), DebridCloudProvider(debridClient: debridClient)]
        self.providers.sort { $0.priority > $1.priority }
    }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
    public func register(provider: any MediaProviderProtocol) {
        locked {
            providers.removeAll { $0.id == provider.id }
            providers.append(provider)
            providers.sort { $0.priority > $1.priority }
        }
    }
    public func allProviders() -> [ProviderStatus] {
        locked {
            providers.map { ProviderStatus(id: $0.id, displayName: $0.displayName, version: $0.version,
                                          isEnabled: $0.isEnabled && !disabledIds.contains($0.id), isAvailable: !$0.capabilities.isEmpty) }
        }
    }
    public func setProviderEnabled(id: String, enabled: Bool) {
        locked {
            if enabled { disabledIds.remove(id) } else { disabledIds.insert(id) }
            preferences?.set(Array(disabledIds).sorted(), forKey: "disabledProviderIds")
        }
    }
    private func active(_ capability: ProviderCapabilities) -> [any MediaProviderProtocol] {
        locked { providers.filter { $0.isEnabled && !disabledIds.contains($0.id) && $0.capabilities.contains(capability) } }
    }
    public func latestSourceWarnings() -> [String] { locked { sourceWarnings } }
    private struct Batch<T: Sendable>: Sendable { let items: [T]; let error: String? }
    private func collect<T: Sendable>(_ providers: [any MediaProviderProtocol], reportSourceWarnings: Bool = false, operation: @escaping @Sendable (any MediaProviderProtocol) async throws -> [T]) async throws -> [T] {
        try await withThrowingTaskGroup(of: Batch<T>.self) { group in
            for provider in providers {
                group.addTask {
                    do { return Batch(items: try await operation(provider), error: nil) }
                    catch {
                        try Task.checkCancellation()
                        return Batch(items: [], error: "\(provider.displayName): \(error.localizedDescription)")
                    }
                }
            }
            var results: [T] = [], errors: [String] = []
            for try await batch in group {
                results += batch.items
                if let error = batch.error { errors.append(error) }
            }
            try Task.checkCancellation()
            if reportSourceWarnings { locked { sourceWarnings = errors } }
            if results.isEmpty, let error = errors.first { throw ProviderServiceError.unavailable(error) }
            return results
        }
    }
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] {
        let items = try await collect(active(.catalogBrowsing)) { try await $0.fetchCatalog(category: category) }
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
    public func search(query: String) async throws -> [MediaItem] {
        if let magnet = SourceStream.normalizedMagnet(query) {
            return [MediaItem(id: magnet, title: "Imported Magnet", type: .directStream, providerId: "builtin.magnet")]
        }
        let results = try await collect(active(.search)) { try await $0.search(query: query) }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        let batch = try await discoverSourceResult(for: item, episode: episode)
        return batch.sources
    }
    public func discoverSourceResult(for item: MediaItem, episode: Episode?) async throws -> SourceDiscoveryResult {
        let providers = active(.sourceDiscovery).filter { $0.supportedTypes.contains(item.type) }
        let batches = try await withThrowingTaskGroup(of: SourceDiscoveryResult.self) { group in
            for provider in providers {
                group.addTask {
                    do { return try await provider.discoverSourceResult(for: item, episode: episode) }
                    catch {
                        try Task.checkCancellation()
                        return SourceDiscoveryResult(sources: [], warnings: ["\(provider.displayName): \(error.localizedDescription)"])
                    }
                }
            }
            var results: [SourceDiscoveryResult] = []
            for try await batch in group { results.append(batch) }
            return results
        }
        try Task.checkCancellation()
        let warnings = batches.flatMap(\.warnings).sorted()
        locked { sourceWarnings = warnings }
        let sources = batches.flatMap(\.sources)
        var seen = Set<String>()
        let sorted = sources.filter {
            let key = "\($0.providerId ?? ""):\($0.cloudTorrentId ?? $0.infoHash ?? $0.directURL?.absoluteString ?? $0.id):\($0.fileIndex ?? -1)"
            return seen.insert(key).inserted
        }.sorted { a, b in
            if a.isRealDebridCached != b.isRealDebridCached { return a.isRealDebridCached }
            if a.resolution != b.resolution { return a.resolution > b.resolution }
            if a.quality != b.quality { return a.quality > b.quality }
            return (a.seeds ?? 0) > (b.seeds ?? 0)
        }
        if sorted.isEmpty, let warning = warnings.first, batches.allSatisfy({ $0.reports.isEmpty }) {
            throw ProviderServiceError.unavailable(warning)
        }
        return SourceDiscoveryResult(sources: sorted, warnings: warnings, reports: batches.flatMap(\.reports))
    }
    public func resolve(source: SourceStream) async throws -> PlayableStream {
        guard let provider = active(.directPlayback).first(where: { $0.id == source.providerId }) else {
            throw ProviderServiceError.unavailable("The source provider is unavailable or disabled. Find streams again.")
        }
        return try await provider.resolve(source: source, using: debridClient)
    }
}
