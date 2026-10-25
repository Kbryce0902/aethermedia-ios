import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AetherMedia

final class RedLightProviderTests: XCTestCase {
    private let fixtureHash = String(repeating: "A", count: 40)
    private let otherHash = String(repeating: "B", count: 40)
    private var movie: MediaItem { MediaItem(id: "tt1234567", title: "Example Film", releaseYear: 2020, imdbId: "tt1234567") }
    private var show: MediaItem { MediaItem(id: "tt1234567", title: "Example Show", releaseYear: 2020, type: .tvShow, imdbId: "tt1234567") }
    private var episode: Episode { Episode(id: "tt1234567:1:2", seasonNumber: 1, episodeNumber: 2, title: "Second") }
    private func client(_ backends: Set<RedLightBackend>, packs: Bool = true) -> RedLightSourceClient {
        var config = RedLightConfiguration(); config.enabled = backends; config.includeSeasonPacks = packs
        let fixed = config
        return RedLightSourceClient(session: URLProtocolStub.session(), configuration: { fixed })
    }
    private func queries(_ request: URLRequest) -> [String: String] {
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
    func testAllSevenMovieServicesUseTheirActualProtocolsWithoutDebridCredentials() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let host = request.url!.host!, path = request.url!.path
            counts.increment(host)
            if host == "apibay.org" {
                XCTAssertEqual(path, "/q.php"); XCTAssertEqual(self.queries(request)["q"], "Example Film 2020")
                XCTAssertEqual(self.queries(request)["cat"], "0")
                return .init([["id": "1", "name": "Example.Film.2020.1080p", "info_hash": self.fixtureHash, "seeders": "5", "size": "1234"]])
            }
            if host == "zilean.stremio.ru" {
                XCTAssertEqual(path, "/dmm/filtered"); XCTAssertEqual(self.queries(request)["ImdbId"], "tt1234567")
                return .init(["results": [["raw_title": "Example.Film.2020.1080p", "info_hash": self.fixtureHash, "size": 4567]]])
            }
            if host == "stremthru.stremio.ru" {
                XCTAssertEqual(path, "/v0/torrents"); XCTAssertEqual(self.queries(request)["sid"], "tt1234567")
                return .init(["data": ["items": [["name": "Example.Film.2020.1080p", "hash": self.fixtureHash, "seeders": 6]]]])
            }
            if host == "www.torrentdownloads.pro" {
                XCTAssertEqual(path, "/rss.xml"); XCTAssertEqual(self.queries(request)["cid"], "4")
                var reply = URLProtocolStub.Reply([:]); reply.body = Data("<rss><channel><item><title><![CDATA[Example.Film.2020.1080p]]></title><size>1234</size><seeders>7</seeders><info_hash>\(self.fixtureHash)</info_hash></item></channel></rss>".utf8)
                return reply
            }
            XCTAssertEqual(path, "/stream/movie/tt1234567.json")
            return .init(["streams": [["description": "📄 Example.Film.2020.1080p.mkv\n📹 h264\n👤 8 💾 1.5 GB", "infoHash": self.fixtureHash, "fileIdx": 2]]])
        }
        let result = try await client([.comet, .mediafusion, .zilean, .torz, .torrentio, .piratebay, .torrentdownloads]).discover(for: movie, episode: nil)
        XCTAssertEqual(result.reports.count, 7); XCTAssertEqual(result.sources.count, 7); XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.reports.allSatisfy { $0.status == "responded" && $0.accepted == 1 })
        XCTAssertEqual(counts.get("torrentio.strem.fun"), 1)
        let comet = result.sources.first { $0.providerName.contains("Comet") }!
        XCTAssertEqual(comet.sizeBytes, 1_610_612_736); XCTAssertEqual(comet.seeds, 8); XCTAssertEqual(comet.fileIndex, 2)
        XCTAssertEqual(comet.providerId, "native.redlight"); XCTAssertFalse(comet.isRealDebridCached)
    }
    func testIDScopedEpisodeSearchAcceptsYearlessEpisodesAndSeasonPacks() async throws {
        URLProtocolStub.configure { request in
            XCTAssertEqual(request.url!.path, "/stream/series/tt1234567:1:2.json")
            return .init(["streams": [
                ["infoHash": self.fixtureHash, "fileIdx": 3, "behaviorHints": ["filename": "Example.Show.S01E02.1080p.mkv", "videoSize": 4000]],
                ["infoHash": self.otherHash, "description": "Example.Show.S01.Complete.1080p"],
                ["infoHash": String(repeating: "C", count: 40), "description": "Example.Show.S01E03.1080p"],
                ["infoHash": String(repeating: "D", count: 40), "description": "Example.Show.1990.S01E02.1080p"]
            ]])
        }
        let result = try await client([.comet]).discover(for: show, episode: episode)
        XCTAssertEqual(result.sources.count, 2)
        let pack = result.sources.first { $0.infoHash == otherHash }!
        XCTAssertNil(pack.fileIndex); XCTAssertNil(pack.originalFileName)
        XCTAssertEqual(pack.targetSeason, 1); XCTAssertEqual(pack.targetEpisode, 2)
        XCTAssertEqual(result.sources.first { $0.infoHash == fixtureHash }?.fileIndex, 3)
        let withoutPacks = try await client([.comet], packs: false).discover(for: show, episode: episode)
        XCTAssertEqual(withoutPacks.sources.count, 1)
    }
    func testNameIndexUsesReleaseNameAndPreservesEditionChecks() async throws {
        let calls = RequestCounts()
        URLProtocolStub.configure { request in
            let q = self.queries(request)["q"]!
            calls.increment(q)
            XCTAssertFalse(q.contains("tt1234567"))
            return .init([
                ["id": "1", "name": "Example.Show.2020.S01E02.1080p", "info_hash": self.fixtureHash],
                ["id": "2", "name": "Example.Show.S01E02.1080p", "info_hash": self.otherHash],
                ["id": "3", "name": "Example.Show.1990.S01E02.1080p", "info_hash": self.otherHash],
                ["id": "4", "name": "Example.Show.S01E02.1080p", "info_hash": String(repeating: "C", count: 40), "imdb": "tt1234567"]
            ])
        }
        let result = try await client([.piratebay]).discover(for: show, episode: episode)
        XCTAssertEqual(result.sources.count, 2)
        XCTAssertEqual(calls.get("Example Show S01E02"), 1); XCTAssertEqual(calls.get("Example Show S01"), 1)
    }
    func testOneFailedServiceKeepsOtherResultsAndSanitizedDiagnostics() async throws {
        URLProtocolStub.configure { request in
            if request.url!.host == "comet.feels.legal" { return .init(["error": "private response must not be echoed"], status: 503) }
            return .init(["data": ["items": [["name": "Example.Film.2020.1080p", "hash": self.fixtureHash]]]])
        }
        let result = try await client([.comet, .torz]).discover(for: movie, episode: nil)
        XCTAssertEqual(result.sources.count, 1); XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("503")); XCTAssertFalse(result.warnings[0].contains("private response"))
        XCTAssertEqual(result.reports.first { $0.id == "comet" }?.status, "failed")
    }
    func testMalformedJSONDoesNotAppearAsAValidEmptyService() async throws {
        URLProtocolStub.configure { _ in
            var reply = URLProtocolStub.Reply([:]); reply.body = Data("<html>blocked</html>".utf8); return reply
        }
        let result = try await client([.comet]).discover(for: movie, episode: nil)
        XCTAssertTrue(result.sources.isEmpty); XCTAssertEqual(result.reports.first?.status, "failed")
        XCTAssertTrue(result.warnings.first!.contains("unreadable"))
    }
    func testAnimeRSSAndJSONAreParsedIndependently() async throws {
        URLProtocolStub.configure { request in
            if request.url!.host == "feed.animetosho.org" {
                XCTAssertEqual(request.url!.path, "/json")
                return .init([["title": "[Group] Example Show 2020 S01E02 1080p", "info_hash": self.fixtureHash, "total_size": 1234]])
            }
            XCTAssertEqual(self.queries(request)["page"], "rss")
            var reply = URLProtocolStub.Reply([:]); reply.body = Data("<rss xmlns:nyaa='https://nyaa.si/xmlns/nyaa'><channel><item><title>[Group] Example Show 2020 S01E02 1080p</title><nyaa:infoHash>\(self.otherHash)</nyaa:infoHash><nyaa:size>1.5 GiB</nyaa:size><nyaa:seeders>8</nyaa:seeders></item></channel></rss>".utf8); return reply
        }
        let anime = MediaItem(id: show.id, title: show.title, releaseYear: 2020, type: .anime, imdbId: show.imdbId)
        let result = try await client([.nyaa, .animetosho], packs: false).discover(for: anime, episode: episode)
        XCTAssertEqual(result.sources.count, 2); XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.sources.first { $0.infoHash == otherHash }?.sizeBytes, 1_610_612_736)
        let nonAnime = try await client([.nyaa, .animetosho]).discover(for: show, episode: episode)
        XCTAssertTrue(nonAnime.sources.isEmpty)
    }
    func testAIOUsesSearchAPIAndOnlyItsOwnBasicCredentials() async throws {
        var config = RedLightConfiguration(); config.enabled = [.aiostreams, .torz]
        config.aioUsername = "fixture-user"; config.aioPassword = "fixture-pass"
        config.endpoints["aiostreams"] = "https://aio.fixture.invalid"
        let fixed = config
        URLProtocolStub.configure { request in
            if request.url!.host == "aio.fixture.invalid" {
                XCTAssertEqual(request.url!.path, "/api/v1/search")
                XCTAssertEqual(self.queries(request)["id"], "tt1234567:1:2"); XCTAssertEqual(self.queries(request)["type"], "series")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("fixture-user:fixture-pass".utf8).base64EncodedString())
                return .init(["success": true, "data": ["results": [
                    ["parsedFile": ["filename": "Example.Show.S01E02.1080p.mkv"], "streamData": ["url": "https://video.fixture.invalid/episode.mkv", "size": 1234]],
                    ["filename": "Example.Show.S01E02.720p.mkv", "url": "https://video.fixture.invalid/p2p", "type": "p2p"],
                    ["filename": "Example.Show.S01E02.720p.mkv", "url": "http://video.fixture.invalid/unsafe"],
                    ["filename": "Example.Show.S01E02.720p.mkv", "url": "https://video.fixture.invalid/header", "requestHeaders": ["Authorization": "fixture-only"]]
                ]]])
            }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); return .init(["data": ["items": []]])
        }
        let result = try await RedLightSourceClient(session: URLProtocolStub.session(), configuration: { fixed }).discover(for: show, episode: episode)
        XCTAssertEqual(result.sources.count, 1); XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("Header-dependent"))
        let playable = try await RedLightNativeProvider().resolve(source: result.sources[0], using: MockRealDebridClient())
        XCTAssertEqual(playable.streamURL.host, "video.fixture.invalid")
    }
    func testPrivateManifestPathAndLegacyEndpointAreSavedOnlyToKeychain() throws {
        let name = "RedLight.Tests.\(UUID().uuidString)", vault = KeychainService(isTesting: true)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://api.fixture.invalid", forKey: "native.redlight.endpoint")
        let store = RedLightSettingsStore(keychain: vault, preferences: defaults)
        var config = store.load(); XCTAssertEqual(config.endpoint(for: .piratebay), "https://api.fixture.invalid")
        config.endpoints["comet"] = "https://comet.fixture.invalid/private-config/manifest.json"
        XCTAssertEqual(try config.validatedEndpoint(for: .comet).path, "/private-config")
        try store.save(config)
        XCTAssertNil(defaults.string(forKey: "native.redlight.endpoint"))
        XCTAssertNotNil(vault.get(key: .redLightConfiguration))
        XCTAssertEqual(store.load().endpoint(for: .comet), config.endpoint(for: .comet))
        for invalid in ["http://example.invalid", "https://" + "user:" + "password@example.invalid", "https://example.invalid?key=value"] {
            config.endpoints["comet"] = invalid; XCTAssertThrowsError(try store.save(config))
        }
    }
    func testBadHashAndWrongMovieIdentityCannotCreateSources() async throws {
        URLProtocolStub.configure { _ in .init(["streams": [
            ["infoHash": "bad", "title": "Example.Film.2020.1080p"],
            ["infoHash": String(repeating: "0", count: 40), "title": "Example.Film.2020.1080p"],
            ["infoHash": self.fixtureHash, "title": "Example.Film.1990.1080p"],
            ["infoHash": self.fixtureHash, "title": "Different.Film.2020.1080p"],
            ["infoHash": self.fixtureHash, "title": "Example.Film.2020.sample.1080p"]
        ]]) }
        let result = try await client([.comet]).discover(for: movie, episode: nil)
        XCTAssertTrue(result.sources.isEmpty); XCTAssertEqual(result.reports.first?.status, "responded")
    }
    func testPackFileSelectionIsUniqueAndRejectsAContradictoryIndex() throws {
        let files = [RDTorrentFile(id: 7, path: "/Example.Show.S01E01.mkv", bytes: 100, selected: 1),
                     RDTorrentFile(id: 42, path: "/Example.Show.S01E02.mkv", bytes: 200, selected: 1),
                     RDTorrentFile(id: 99, path: "/Sample/Example.Show.S01E02.mkv", bytes: 1, selected: 0)]
        func info(_ files: [RDTorrentFile]) -> RDTorrentInfo {
            RDTorrentInfo(id: "pack", filename: "Example.Show.S01", originalFilename: nil, hash: fixtureHash, bytes: 301, host: "", progress: 100, status: "downloaded", added: "", files: files, links: ["first", "second"], ended: nil, speed: nil, seeders: nil)
        }
        let selected = try info(files).requestedVideo(fileIndex: nil, fileName: nil, season: 1, episode: 2)
        XCTAssertEqual(selected.id, 42); XCTAssertEqual(try info(files).link(forFileId: selected.id), "second")
        XCTAssertThrowsError(try info(files).requestedVideo(fileIndex: 0, fileName: nil, season: 1, episode: 2))
        XCTAssertThrowsError(try info(files).requestedVideo(fileIndex: nil, fileName: nil, season: 1, episode: 3))
        XCTAssertThrowsError(try info(files + [RDTorrentFile(id: 100, path: "/alt/Example.Show.S01E02.mkv", bytes: 200, selected: 0)]).requestedVideo(fileIndex: nil, fileName: nil, season: 1, episode: 2))
    }
    func testSourceResultsKeepBackendDetailsThroughProviderManager() async throws {
        URLProtocolStub.configure { _ in .init(["streams": [["title": "Example.Film.2020.1080p", "infoHash": self.fixtureHash]]]) }
        let provider = RedLightNativeProvider(client: client([.comet]))
        let manager = ProviderManager(providers: [provider], preferences: nil)
        let result = try await manager.discoverSourceResult(for: movie, episode: nil)
        XCTAssertEqual(result.sources.first?.providerId, "native.redlight"); XCTAssertEqual(result.reports.first?.name, "Comet")
        XCTAssertEqual(result.reports.first?.accepted, 1)
    }
    func testCancellationCancelsNetworkSearchInsteadOfBecomingAnEmptyResult() async throws {
        URLProtocolStub.configure { _ in .init(["streams": []], delay: 0.2) }
        let production = client([.comet])
        let task = Task { try await production.discover(for: movie, episode: nil) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation should propagate") } catch {}
    }
    func testFailedSeasonQueryRetainsExactEpisodeResults() async throws {
        URLProtocolStub.configure { request in
            if self.queries(request)["q"] == "Example Show S01" { return .init([:], status: 503) }
            return .init([["id": "1", "name": "Example.Show.2020.S01E02.1080p", "info_hash": self.fixtureHash]])
        }
        let result = try await client([.piratebay]).discover(for: show, episode: episode)
        XCTAssertEqual(result.sources.count, 1); XCTAssertEqual(result.reports.first?.status, "partial")
        XCTAssertEqual(result.warnings.count, 1)
    }
}
