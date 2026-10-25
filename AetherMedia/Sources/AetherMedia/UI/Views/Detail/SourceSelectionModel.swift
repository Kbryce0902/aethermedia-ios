import Foundation
import Combine

public struct SourceResolutionFailure: Sendable {
    public let sourceId: String
    public let message: String
    public let diagnosticDetails: String?
}

/// Discovery and playback failures are independent: a rejected source must not
/// replace the list of successfully discovered alternatives.
@MainActor
public final class SourceSelectionModel: ObservableObject {
    @Published public private(set) var sources: [SourceStream] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var providerWarnings: [String] = []
    @Published public private(set) var backendReports: [SourceBackendReport] = []
    @Published public private(set) var discoveryError: String?
    @Published public private(set) var resolutionFailure: SourceResolutionFailure?
    @Published public private(set) var resolvingSourceId: String?

    private let item: MediaItem
    private let episode: Episode?
    private let manager: ProviderManager
    private var discoveryGeneration = UUID()
    private var resolutionGeneration = UUID()

    public init(item: MediaItem, episode: Episode?, manager: ProviderManager) {
        self.item = item
        self.episode = episode
        self.manager = manager
    }

    public func discoverSources() async {
        let generation = UUID()
        discoveryGeneration = generation
        isLoading = true
        discoveryError = nil
        defer { if discoveryGeneration == generation { isLoading = false } }
        do {
            let discovered = try await manager.discoverSourceResult(for: item, episode: episode)
            try Task.checkCancellation()
            guard generation == discoveryGeneration else { return }
            sources = discovered.sources
            providerWarnings = discovered.warnings
            backendReports = discovered.reports
        } catch {
            guard !Task.isCancelled, generation == discoveryGeneration else { return }
            // A failed refresh preserves the previous list.
            discoveryError = error.localizedDescription
        }
    }

    public func resolveSource(_ source: SourceStream) async -> PlayableStream? {
        guard resolvingSourceId == nil else { return nil }
        let generation = UUID()
        resolutionGeneration = generation
        resolvingSourceId = source.id
        resolutionFailure = nil
        defer { if generation == resolutionGeneration { resolvingSourceId = nil } }
        do {
            let playable = try await manager.resolve(source: source)
            try Task.checkCancellation()
            guard generation == resolutionGeneration else { return nil }
            return playable
        } catch {
            guard !Task.isCancelled, generation == resolutionGeneration else { return nil }
            let diagnostic = (error as? RealDebridError)?.diagnosticDetails
            resolutionFailure = SourceResolutionFailure(sourceId: source.id, message: error.localizedDescription,
                                                        diagnosticDetails: diagnostic)
            return nil
        }
    }

    public func dismissResolutionFailure() { resolutionFailure = nil }

    public func cancelResolution() {
        resolutionGeneration = UUID()
        resolvingSourceId = nil
    }
}
