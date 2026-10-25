import XCTest
import Foundation
@testable import AetherMedia

final class NativeAddonProviderTests: XCTestCase {
    private let fixtureHash = String(repeating: "A", count: 40)
    private var movie: MediaItem { MediaItem(id: "tt1234567", title: "Example Film", releaseYear: 2020, imdbId: "tt1234567") }
    private var episode: Episode { Episode(id: "tt1234567:1:1", seasonNumber: 1, episodeNumber: 1, title: "Pilot") }
    private func client() -> NativeIndexClient { NativeIndexClient(session: URLProtocolStub.session(), preferences: nil) }
    func testSerenMovieUsesIMDbAndKeepsOnlyMatchingRecord() async throws {
        URLProtocolStub.configure { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.path, "/api/v2/list_movies.json")
            XCTAssertTrue(request.url!.query!.contains("tt1234567"))
            return .init(["status":"ok","data":["movies":[
                ["imdb_code":"tt1234567","title_long":"Example Film (2020)","torrents":[["hash":self.fixtureHash,"quality":"1080p","type":"bluray","size_bytes":1234,"seeds":10]]],
                ["imdb_code":"tt9999999","title_long":"Wrong Film","torrents":[["hash":self.fixtureHash]]]
            ]]])
        }
        let results = try await SerenNativeProvider(client: client()).discoverSources(for: movie, episode: nil)
        XCTAssertEqual(results.count,1)
        XCTAssertEqual(results.first?.providerId,"native.seren")
        XCTAssertEqual(results.first?.seeds,10)
        XCTAssertFalse(results.first!.isRealDebridCached)
    }
    func testSerenEpisodeRejectsWrongEpisodeAndSeasonPackAndPages() async throws {
        URLProtocolStub.configure { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if page == "1" { return .init(["torrents_count":101,"torrents":[["season":"1","episode":"10","filename":"Example.Show.S01E10.1080p","hash":self.fixtureHash]]]) }
            return .init(["torrents_count":101,"torrents":[
                ["season":"1","episode":"1","filename":"Example.Show.S01E01.1080p","hash":self.fixtureHash,"size_bytes":"2345","seeds":"20"],
                ["season":"1","episode":"0","filename":"Example.Show.Season.1.Complete","hash":self.fixtureHash]
            ]])
        }
        let show = MediaItem(id:"tt1234567",title:"Example Show",type:.tvShow,imdbId:"tt1234567")
        let results = try await SerenNativeProvider(client: client()).discoverSources(for:show,episode:episode)
        XCTAssertEqual(results.count,1)
        XCTAssertEqual(results.first?.sizeBytes,2345)
        XCTAssertEqual(results.first?.providerId,"native.seren")
    }


    func testNativeResolutionPreservesOwnershipAndCodecMetadata() async throws {
        let source = SourceStream(title:"Example.Film.1080p.DTS",providerName:"Seren Native",magnetURL:"magnet:?xt=urn:btih:\(fixtureHash)",providerId:"native.seren")
        let result = try await SerenNativeProvider(client:client()).resolve(source:source,using:MockRealDebridClient())
        XCTAssertEqual(result.originalSource?.providerId,"native.seren")
        XCTAssertEqual(result.originalSource?.audioCodec,"DTS")
    }
    func testUnavailableIndexHasVisibleFailure() async {
        URLProtocolStub.configure { _ in .init([:],status:503) }
        do { _ = try await SerenNativeProvider(client:client()).discoverSources(for:movie,episode:nil);XCTFail("Expected provider failure") } catch { XCTAssertTrue(error.localizedDescription.contains("503")) }
    }

    func testSeriesEditionCannotMixDoctorWhoRebootsOrTrustConflictingIMDb() {
        let show = MediaItem(id: "tt1234567", title: "Doctor Who", releaseYear: 2023, type: .tvShow, imdbId: "tt1234567")
        XCTAssertTrue(NativeReleaseMatcher.matches("Doctor.Who.2023.S01E01.2160p", item: show, episode: episode))
        XCTAssertFalse(NativeReleaseMatcher.matches("Doctor.Who.2005.S01E01.Rose.1080p", item: show, episode: episode))
        XCTAssertFalse(NativeReleaseMatcher.matches("Doctor.Who.1963.S01E01.1080p", item: show, episode: episode))
        XCTAssertFalse(NativeReleaseMatcher.matches("Doctor.Who.S01E01.1080p", item: show, episode: episode))
        XCTAssertTrue(NativeReleaseMatcher.matches("Doctor.Who.S01E01.1080p", item: show, episode: episode, sourceImdbId: show.imdbId))
        XCTAssertFalse(NativeReleaseMatcher.matches("Doctor.Who.2023.S01E01.1080p", item: show, episode: episode, sourceImdbId: "tt9999999"))
        XCTAssertFalse(NativeReleaseMatcher.matches("Doctor.Who.2005.S01E01.1080p", item: show, episode: episode, sourceImdbId: show.imdbId))
    }


    func testEpisodeBoundariesAndAmbiguousMultiEpisodeReleases() {
        XCTAssertTrue(NativeReleaseMatcher.hasExactEpisode("Example.S01E01.1080p",episode:episode))
        XCTAssertTrue(NativeReleaseMatcher.hasExactEpisode("Example.S01E01-1080p",episode:episode))
        XCTAssertFalse(NativeReleaseMatcher.hasExactEpisode("Example.S01E10.1080p",episode:episode))
        XCTAssertFalse(NativeReleaseMatcher.hasExactEpisode("Example.S01E01E02.1080p",episode:episode))
        XCTAssertFalse(NativeReleaseMatcher.hasExactEpisode("Example.S01E01-02.1080p",episode:episode))
        XCTAssertFalse(NativeReleaseMatcher.hasExactEpisode("Example.Season.1.Complete",episode:episode))
    }
}
