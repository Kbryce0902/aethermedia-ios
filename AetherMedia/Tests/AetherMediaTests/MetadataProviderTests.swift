import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AetherMedia

final class MetadataProviderTests: XCTestCase {
    func testCatalogAndArbitraryEmptySearchUseRealResponses() async throws {
        URLProtocolStub.configure { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url!.path.contains("search=") { return .init(["metas": []]) }
            return .init(["metas": [["id": "tt1234567", "name": "Actual Fixture", "type": "movie", "releaseInfo": "2020", "imdbRating": "7.2"]]])
        }
        let metadata = StremioMetadataClient(session: URLProtocolStub.session())
        let provider = BuiltInTorrentioProvider(session: URLProtocolStub.session(), metadata: metadata)
        let catalog = try await provider.fetchCatalog(category: .popularMovies)
        XCTAssertEqual(catalog.first?.title, "Actual Fixture")
        XCTAssertEqual(catalog.first?.rating, 7.2)
        let search = try await provider.search(query: "No Match / & + ?")
        XCTAssertTrue(search.isEmpty, "Empty results must not be replaced with an invented movie")
    }
    func testSeriesMetadataSuppliesRealEpisodeIdsAndSeasons() async throws {
        URLProtocolStub.configure { _ in .init(["meta": ["id": "tt1234567", "name": "Fixture Show", "videos": [
            ["id": "tt1234567:2:3", "title": "Actual episode", "season": 2, "episode": 3]
        ]]]) }
        let details = try await StremioMetadataClient(session: URLProtocolStub.session()).details(for: MediaItem(id: "tt1234567", title: "Fixture Show", type: .tvShow))
        XCTAssertEqual(details.seasons.first?.seasonNumber, 2)
        XCTAssertEqual(details.seasons.first?.episodes.first?.id, "tt1234567:2:3")
        XCTAssertEqual(details.seasons.first?.episodes.first?.title, "Actual episode")
    }
    func testDiscoveryUsesEpisodeIdAndDoesNotInventCacheOrSeeds() async throws {
        let hash = String(repeating: "A", count: 40)
        URLProtocolStub.configure { request in
            XCTAssertTrue(request.url!.path.contains("tt1234567:2:3"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return .init(["streams": [["infoHash": hash, "fileIdx": 0, "title": "Actual.Release.1080p", "behaviorHints": ["filename": "release.mp4", "videoSize": 1200]]]])
        }
        let provider = BuiltInTorrentioProvider(session: URLProtocolStub.session())
        let sources = try await provider.discoverSources(for: MediaItem(id: "tt1234567", title: "Fixture", type: .tvShow),
                                episode: Episode(id: "tt1234567:2:3", seasonNumber: 2, episodeNumber: 3, title: "Episode"))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.providerId, provider.id)
        XCTAssertEqual(sources.first?.fileIndex, 0)
        XCTAssertEqual(sources.first?.isRealDebridCached, false)
        XCTAssertNil(sources.first?.seeds)
    }
    func testMetadataHTTPFailureIsNotReportedAsAnEmptyCatalog() async {
        URLProtocolStub.configure { _ in .init([:], status: 503) }
        do { _ = try await StremioMetadataClient(session: URLProtocolStub.session()).catalog(category: .popularMovies); XCTFail("Expected visible error") } catch {}
    }
}
