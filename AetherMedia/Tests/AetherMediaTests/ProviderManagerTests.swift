import XCTest
@testable import AetherMedia

final class ProviderManagerTests: XCTestCase {
    private func manager(_ providers: [any MediaProviderProtocol]) -> ProviderManager {
        ProviderManager(debridClient: MockRealDebridClient(), providers: providers, preferences: nil)
    }
    func testDefaultRegistryHasNativeAddonProviders() {
        let providers = ProviderManager(debridClient: MockRealDebridClient(), preferences: nil).allProviders()
        XCTAssertEqual(providers.count, 5)
        XCTAssertEqual(providers.first { $0.id == "native.seren" }?.isAvailable, true)
        XCTAssertEqual(providers.first { $0.id == "native.redlight" }?.isEnabled, true)
    }
    func testPartialProviderFailureKeepsResultsAndDeduplicates() async throws {
        let item = MediaItem(id: "tt1234567", title: "Fixture")
        let manager = manager([FixtureProvider(id: "a", items: [item]), FixtureProvider(id: "b", items: [item]), FixtureProvider(id: "failed", fails: true)])
        let items = try await manager.fetchCatalog(category: .popularMovies)
        XCTAssertEqual(items, [item])
    }
    func testAllProviderFailuresAreVisible() async {
        do { _ = try await manager([FixtureProvider(id: "failed", fails: true)]).search(query: "Fixture"); XCTFail("Expected service error") } catch {}
    }
    func testSourceResolutionUsesProviderIdRatherThanDisplayName() async throws {
        let manager = manager([FixtureProvider(id: "wrong"), FixtureProvider(id: "right")])
        let source = SourceStream(title: "Fixture", providerName: "Misleading label", providerId: "right")
        let playable = try await manager.resolve(source: source)
        XCTAssertEqual(playable.streamURL.lastPathComponent, "right.mp4")
    }
    func testDisabledProviderCannotResolveThroughFallback() async {
        let manager = manager([FixtureProvider(id: "disabled"), FixtureProvider(id: "other")])
        manager.setProviderEnabled(id: "disabled", enabled: false)
        do {
            _ = try await manager.resolve(source: SourceStream(title: "Fixture", providerName: "other", providerId: "disabled"))
            XCTFail("Disabled provider must not be substituted")
        } catch {}
    }
    func testEnablementSurvivesManagerRecreation() {
        let name = "AetherMedia.Tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let first = ProviderManager(providers: [FixtureProvider(id: "fixture")], preferences: preferences)
        first.setProviderEnabled(id: "fixture", enabled: false)
        let second = ProviderManager(providers: [FixtureProvider(id: "fixture")], preferences: preferences)
        XCTAssertEqual(second.allProviders().first?.isEnabled, false)
    }
    func testMagnetSearchHasManualProviderIdentity() async throws {
        let hash = String(repeating: "A", count: 40)
        let results = try await manager([]).search(query: hash)
        XCTAssertEqual(results.first?.id, "magnet:?xt=urn:btih:\(hash)")
        XCTAssertEqual(results.first?.providerId, "builtin.magnet")
    }
}

private struct FixtureProvider: MediaProviderProtocol {
    let id: String
    var items: [MediaItem] = []
    var fails = false
    var displayName: String { "Shared display name" }
    var version: String { "fixture" }
    var capabilities: ProviderCapabilities { .all }
    var isEnabled: Bool { true }
    var priority: Int { 1 }
    var supportedTypes: [MediaType] { [.movie] }
    func search(query: String) async throws -> [MediaItem] { try await fetchCatalog(category: .popularMovies) }
    func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] {
        if fails { throw ProviderServiceError.unavailable("Fixture unavailable") }
        return items
    }
    func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] { [] }
    func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        PlayableStream(streamURL: URL(string: "https://fixture.invalid/\(id).mp4")!, title: id, filename: "fixture.mp4")
    }
}
