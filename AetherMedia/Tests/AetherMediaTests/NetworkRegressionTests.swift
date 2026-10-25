import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AetherMedia

final class NetworkRegressionTests: XCTestCase {
    private let testInfoHash = String(repeating: "A", count: 40)
    private func keychain() -> KeychainService {
        let keychain = KeychainService(isTesting: true)
        keychain.save(key: .rdAccessToken, value: "old")
        keychain.save(key: .rdRefreshToken, value: "refresh")
        keychain.save(key: .rdClientId, value: "client")
        keychain.save(key: .rdClientSecret, value: "secret")
        return keychain
    }
    private func client(keychain: KeychainService? = nil, attempts: Int = 5) -> RealDebridClient {
        RealDebridClient(session: URLProtocolStub.session(), keychain: keychain ?? self.keychain(), pollIntervalNanoseconds: 0, maxPreparationAttempts: attempts)
    }
    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let pairs = URLComponents(string: "https://fixture.invalid/?" + body)?.queryItems ?? []
        return Dictionary(pairs.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
    private var profile: [String: Any] { ["id": 1, "username": "Fixture", "points": 0, "type": "premium"] }
    private var token: [String: Any] { ["access_token": "new", "refresh_token": "new-refresh", "token_type": "Bearer", "expires_in": 3600] }
    private func info(status: String, selected: Set<Int> = [7, 42], links: [String] = ["https://real-debrid.com/d/one", "https://real-debrid.com/d/two"]) -> [String: Any] {
        ["id": "TOR_RENT_ID", "filename": "Fixture Pack", "hash": testInfoHash, "bytes": 300, "host": "real-debrid.com",
         "progress": status == "downloaded" ? 100 : 10, "status": status, "added": "2026-10-24T12:00:00Z",
         "files": [["id": 7, "path": "/first.mp4", "bytes": 100, "selected": selected.contains(7) ? 1 : 0],
                   ["id": 42, "path": "/second.mp4", "bytes": 200, "selected": selected.contains(42) ? 1 : 0]], "links": links]
    }
    private func unrestricted(_ link: String) -> [String: Any] {
        ["id": "play", "filename": "fixture.mp4", "filesize": 200, "link": link, "host": "real-debrid.com", "download": "https://fixture.invalid/video.mp4", "streamable": 1]
    }
    func testPaginationUsesQueryNotEncodedPath() async throws {
        URLProtocolStub.configure { request in
            XCTAssertEqual(request.url?.path, "/rest/1.0/torrents")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.first { $0.name == "offset" }?.value, "20")
            XCTAssertEqual(items.first { $0.name == "limit" }?.value, "50")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old")
            return .init([])
        }
        let torrents = try await client().getTorrents(offset: 20, limit: 50)
        XCTAssertTrue(torrents.isEmpty)
    }
    func testMagnetFormPreservesTrackersAndPlusSigns() async throws {
        let magnet = "magnet:?xt=urn:btih:\(testInfoHash)&dn=Name+Test&tr=https%3A%2F%2Ffixture.invalid%2Fa%3Fx%3D1%26y%3D2"
        URLProtocolStub.configure { request in
            XCTAssertEqual(self.form(request)["magnet"], magnet)
            return .init(["id": "NEW"])
        }
        let id = try await client().addMagnet(magnet)
        XCTAssertEqual(id, "NEW")
    }
    func testRefreshUsesDocumentedDeviceGrantAndRetriesOnce() async throws {
        let counts = RequestCounts(), keychain = keychain()
        URLProtocolStub.configure { request in
            if request.url?.path == "/oauth/v2/token" {
                counts.increment("token")
                XCTAssertEqual(self.form(request)["grant_type"], "http://oauth.net/grant_type/device/1.0")
                XCTAssertEqual(self.form(request)["code"], "refresh")
                return .init(self.token)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" { return .init(["error": "bad_token"], status: 401) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
            return .init(self.profile)
        }
        let user = try await client(keychain: keychain).getUserProfile()
        XCTAssertEqual(user.username, "Fixture")
        XCTAssertEqual(counts.get("token"), 1)
        XCTAssertEqual(keychain.get(key: .rdRefreshToken), "new-refresh")
    }
    func testConcurrentUnauthorizedRequestsShareOneRefresh() async throws {
        let counts = RequestCounts(), client = client()
        URLProtocolStub.configure { request in
            if request.url?.path == "/oauth/v2/token" { counts.increment("token"); return .init(self.token, delay: 0.1) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer old" ? .init([:], status: 401) : .init(self.profile)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await client.getUserProfile() } }
            try await group.waitForAll()
        }
        XCTAssertEqual(counts.get("token"), 1)
    }
    func testTransientRefreshFailureDoesNotWipeCredentials() async {
        let keychain = keychain()
        let production = self.client(keychain: keychain)
        URLProtocolStub.configure { _ in .init([:], status: 503) }
        do { try await production.refreshToken(); XCTFail("Expected error") } catch {}
        XCTAssertEqual(keychain.get(key: .rdRefreshToken), "refresh")
        XCTAssertTrue(production.isAuthenticated)
    }
    func testLogoutInvalidatesInFlightRefresh() async throws {
        let keychain = keychain(), counts = RequestCounts()
        let client = self.client(keychain: keychain)
        URLProtocolStub.configure { _ in counts.increment("token"); return .init(self.token, delay: 0.5) }
        let request = Task { try await client.refreshToken() }
        for _ in 0..<100 {
            if counts.get("token") > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(counts.get("token"), 1)
        client.logout()
        do { try await request.value; XCTFail("Expected cancelled refresh") } catch {}
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertNil(keychain.get(key: .rdAccessToken))
    }
    func testMagnetConversionSelectsActualFileIdImmediately() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return .init([]) }
            if path.hasSuffix("addMagnet") { return .init(["id": "TOR_RENT_ID"]) }
            if path.contains("/info/") {
                let call = counts.increment("info")
                if call == 1 { var fixture = self.info(status: "magnet_conversion", selected: [], links: []); fixture["files"] = []; return .init(fixture) }
                if call == 2 { return .init(self.info(status: "waiting_files_selection", selected: [], links: [])) }
                return .init(self.info(status: "downloaded", selected: [42], links: ["https://real-debrid.com/d/two"]))
            }
            if path.contains("selectFiles") { XCTAssertEqual(self.form(request)["files"], "42"); counts.increment("selection"); return .init([:], status: 204) }
            XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/two")
            return .init(self.unrestricted("https://real-debrid.com/d/two"))
        }
        let playable = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(playable.filename, "fixture.mp4")
        XCTAssertEqual(counts.get("info"), 3)
        XCTAssertEqual(counts.get("selection"), 1)
    }
    func testCloudSelectionUsesSecondLinkAndPreservesUnderscoreId() async throws {
        URLProtocolStub.configure { request in
            if request.url!.path.contains("/info/") {
                XCTAssertTrue(request.url!.path.hasSuffix("TOR_RENT_ID"))
                return .init(self.info(status: "downloaded"))
            }
            XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/two")
            return .init(self.unrestricted("https://real-debrid.com/d/two"))
        }
        let client = client()
        let provider = DebridCloudProvider(debridClient: client)
        let source = SourceStream(title: "Second", providerName: provider.displayName, fileIndex: 42,
                                  providerId: provider.id, cloudTorrentId: "TOR_RENT_ID")
        _ = try await provider.resolve(source: source, using: client)
    }
    func testNotReadyTorrentWithLinkDoesNotPlayPrematurely() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([]) }
            if request.url!.path.hasSuffix("addMagnet") { return .init(["id": "TOR_RENT_ID"]) }
            if request.url!.path.contains("/info/") { return .init(self.info(status: "downloading")) }
            counts.increment("unexpectedUnrestrict"); return .init([:])
        }
        do { _ = try await client(attempts: 2).resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: nil); XCTFail("Expected preparation timeout") } catch {}
        XCTAssertEqual(counts.get("unexpectedUnrestrict"), 0)
    }
    func testAmbiguousCloudMappingIsRejected() throws {
        let fixture = info(status: "downloaded", links: ["https://real-debrid.com/d/one"])
        let decoded = try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: fixture))
        XCTAssertThrowsError(try decoded.link(forFileId: 42))
    }
}
