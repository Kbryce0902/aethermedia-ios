import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AetherMedia

final class SourceResolutionRegressionTests: XCTestCase {
    private let testInfoHash = String(repeating: "A", count: 40)
    private func client(keychain: KeychainService? = nil) -> RealDebridClient {
        let vault = keychain ?? KeychainService(isTesting: true)
        vault.save(key: .rdAccessToken, value: "private-token")
        return RealDebridClient(session: URLProtocolStub.session(), keychain: vault, pollIntervalNanoseconds: 0, maxPreparationAttempts: 4)
    }
    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let pairs = URLComponents(string: "https://fixture.invalid/?" + body)?.queryItems ?? []
        return Dictionary(pairs.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
    private func summary(id: String = "EXISTING", hash: String? = nil, status: String = "downloaded") -> [String: Any] {
        ["id": id, "filename": "Fixture", "hash": hash ?? testInfoHash.lowercased(), "bytes": 300, "host": "real-debrid.com",
         "progress": 100, "status": status, "added": "2026-10-25T00:00:00Z", "links": []]
    }
    private func info(id: String = "EXISTING", hash: String? = nil, status: String = "downloaded", selected: Set<Int> = [7, 42]) -> [String: Any] {
        var value = summary(id: id, hash: hash, status: status)
        value["files"] = [["id": 7, "path": "/season/first.mkv", "bytes": 100, "selected": selected.contains(7) ? 1 : 0],
                          ["id": 42, "path": "/season/second.mkv", "bytes": 200, "selected": selected.contains(42) ? 1 : 0]]
        value["links"] = status == "downloaded" ? [7, 42].filter { selected.contains($0) }.map { "https://real-debrid.com/d/file\($0)" } : []
        return value
    }
    private var playback: [String: Any] {
        ["id": "play", "filename": "second.mkv", "filesize": 200, "link": "https://real-debrid.com/d/file42",
         "host": "real-debrid.com", "download": "https://fixture.invalid/second.mkv", "streamable": 1]
    }

    private func emptyReply(status: Int) -> URLProtocolStub.Reply {
        var reply = URLProtocolStub.Reply([:], status: status)
        reply.body = Data()
        return reply
    }

    func testNoContentCloudListIsAnEmptyPageNotADecodingFailure() async throws {
        URLProtocolStub.configure { request in
            XCTAssertEqual(request.url?.path, "/rest/1.0/torrents")
            XCTAssertEqual(request.httpMethod, "GET")
            return self.emptyReply(status: 204)
        }
        let production = client()
        let page = try await production.getTorrentPage(offset: 0, limit: 50)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.rawItemCount, 0)
        XCTAssertEqual(page.ignoredItemCount, 0)
        XCTAssertNil(page.firstFailure)
        XCTAssertNil(page.warningMessage)
        let torrents = try await production.getTorrents(offset: 0, limit: 50)
        XCTAssertTrue(torrents.isEmpty)
    }

    func testNoContentOnLaterCloudPageEndsPaginationAndAllowsNewSource() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" {
                let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!
                counts.increment("page")
                if offset == "0" { return .init((0..<100).map { self.summary(id: "OTHER\($0)", hash: String(repeating: "B", count: 40)) }) }
                XCTAssertEqual(offset, "100")
                return self.emptyReply(status: 204)
            }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"], status: 201) }
            if path.hasSuffix("/info/NEW") { return .init(self.info(id: "NEW", selected: [42])) }
            XCTAssertTrue(path.hasSuffix("unrestrict/link"), "No unrelated cloud entry or selection should be touched")
            XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/file42")
            return .init(self.playback)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
        XCTAssertEqual(counts.get("page"), 2)
        XCTAssertEqual(counts.get("add"), 1)
    }

    func testNoContentCloudPolicySurvivesTokenRefresh() async throws {
        let counts = RequestCounts(), vault = KeychainService(isTesting: true)
        vault.save(key: .rdClientId, value: "fixture-client")
        vault.save(key: .rdClientSecret, value: "fixture-secret")
        vault.save(key: .rdRefreshToken, value: "fixture-refresh")
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" {
                if counts.increment("cloud") == 1 { return self.emptyReply(status: 401) }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer renewed-token")
                return self.emptyReply(status: 204)
            }
            XCTAssertEqual(request.url!.path, "/oauth/v2/token")
            counts.increment("refresh")
            return .init(["access_token": "renewed-token", "refresh_token": "renewed-refresh", "expires_in": 3600, "token_type": "Bearer"])
        }
        let page = try await client(keychain: vault).getTorrentPage(offset: 0, limit: 50)
        XCTAssertEqual(page.rawItemCount, 0)
        XCTAssertEqual(counts.get("cloud"), 2)
        XCTAssertEqual(counts.get("refresh"), 1)
    }

    func testNoContentCloudPolicySurvivesRateLimitRetry() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            XCTAssertEqual(request.url!.path, "/rest/1.0/torrents")
            if counts.increment("cloud") == 1 {
                var reply = self.emptyReply(status: 429); reply.headers["Retry-After"] = "0"
                return reply
            }
            return self.emptyReply(status: 204)
        }
        let page = try await client().getTorrentPage(offset: 0, limit: 50)
        XCTAssertEqual(page.rawItemCount, 0)
        XCTAssertEqual(counts.get("cloud"), 2)
    }

    func testEmptyOKCloudAndMissingNoContentDetailStillFailDecoding() async throws {
        URLProtocolStub.configure { _ in self.emptyReply(status: 200) }
        do { _ = try await client().getTorrentPage(offset: 0, limit: 50); XCTFail("Empty HTTP 200 is not a valid empty collection") }
        catch RealDebridError.responseDecodingFailed(let failure) { XCTAssertEqual(failure.operation, .cloudLookup) }
        URLProtocolStub.configure { _ in self.emptyReply(status: 204) }
        do { _ = try await client().getTorrentInfo(id: "EXISTING"); XCTFail("A missing detail must not become an invented torrent") }
        catch RealDebridError.responseDecodingFailed(let failure) { XCTAssertEqual(failure.operation, .torrentInfo) }
    }

    func testEmptyCloudServiceFailureStillStopsBeforeAddingSource() async throws {
        for status in [403, 451, 503] {
            let counts = RequestCounts()
            URLProtocolStub.configure { request in
                if request.url!.path == "/rest/1.0/torrents" { return self.emptyReply(status: status) }
                counts.increment("unexpected"); return .init(["id": "NEW"])
            }
            do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("A service error is not an empty cloud") }
            catch RealDebridError.requestFailed(let failure) {
                XCTAssertEqual(failure.operation, .cloudLookup)
                XCTAssertEqual(failure.statusCode, status)
            }
            XCTAssertEqual(counts.get("unexpected"), 0)
        }
    }

    func testReadyCloudMatchPlaysExactSecondFileWithoutAddOrSelection() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            counts.increment(path)
            if path == "/rest/1.0/torrents" { return .init([self.summary()]) }
            if path.contains("/info/") { return .init(self.info()) }
            if path.hasSuffix("unrestrict/link") {
                XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/file42")
                return .init(self.playback)
            }
            XCTFail("A ready match must not add/select/delete: \(path)")
            return .init([:], status: 500)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
        XCTAssertEqual(counts.get("/rest/1.0/torrents/addMagnet"), 0)
        XCTAssertEqual(counts.get("/rest/1.0/torrents/info/EXISTING"), 1)
    }

    func testNewTorrentNotFoundImmediatelyAfterAddRetriesSameIdWithoutResubmitting() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return self.emptyReply(status: 204) }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"], status: 201) }
            if path.hasSuffix("/info/NEW") {
                if counts.increment("info") <= 2 { return .init(["error_code": 7], status: 404) }
                return .init(self.info(id: "NEW", selected: [42]))
            }
            XCTAssertTrue(path.hasSuffix("unrestrict/link"), "A not-yet-visible entry must not be selected, deleted or added again")
            XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/file42")
            return .init(self.playback)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
        XCTAssertEqual(counts.get("add"), 1)
        XCTAssertEqual(counts.get("info"), 3)
    }

    func testPersistentNewTorrentNotFoundStopsAtBoundWithOriginalServiceDetails() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return self.emptyReply(status: 204) }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"], status: 201) }
            XCTAssertTrue(path.hasSuffix("/info/NEW"))
            counts.increment("info"); return .init(["error_code": 7], status: 404)
        }
        do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Persistent absence must remain an error") }
        catch RealDebridError.requestFailed(let failure) {
            XCTAssertEqual(failure.operation, .torrentInfo)
            XCTAssertEqual(failure.statusCode, 404); XCTAssertEqual(failure.code, 7)
        }
        XCTAssertEqual(counts.get("add"), 1)
        XCTAssertEqual(counts.get("info"), 4, "The test client caps preparation attempts at four")
    }

    func testOrdinaryMissingTorrentDetailIsNotTreatedAsANewCreation() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/info/EXISTING"))
            counts.increment("info"); return .init(["error_code": 7], status: 404)
        }
        do { _ = try await client().getTorrentInfo(id: "EXISTING"); XCTFail("Expected missing entry") }
        catch RealDebridError.requestFailed(let failure) { XCTAssertEqual(failure.code, 7) }
        XCTAssertEqual(counts.get("info"), 1)
    }

    func testNewTorrentInspectionDoesNotRetryOtherRefusalsOrUnknown404() async throws {
        for (status, code) in [(451, Optional(35)), (503, Optional(25)), (404, Optional<Int>.none), (404, Optional(35))] {
            let counts = RequestCounts()
            URLProtocolStub.configure { request in
                let path = request.url!.path
                if path == "/rest/1.0/torrents" { return self.emptyReply(status: 204) }
                if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"], status: 201) }
                XCTAssertTrue(path.hasSuffix("/info/NEW"))
                counts.increment("info")
                var error: [String: Any] = ["error": "fixture rejection"]
                if let code { error["error_code"] = code }
                return .init(error, status: status)
            }
            do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Expected explicit refusal") }
            catch RealDebridError.requestFailed(let failure) {
                XCTAssertEqual(failure.statusCode, status); XCTAssertEqual(failure.code, code)
            }
            XCTAssertEqual(counts.get("add"), 1); XCTAssertEqual(counts.get("info"), 1)
        }
    }

    func testNewTorrentMalformedDetailIsNotRetriedOrPlayed() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return self.emptyReply(status: 204) }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"], status: 201) }
            XCTAssertTrue(path.hasSuffix("/info/NEW"))
            counts.increment("info")
            var value = self.info(id: "NEW"); value["hash"] = NSNull()
            return .init(value)
        }
        do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Malformed identity must remain an error") }
        catch RealDebridError.responseDecodingFailed(let failure) { XCTAssertEqual(failure.codingPath, "$.hash") }
        XCTAssertEqual(counts.get("add"), 1); XCTAssertEqual(counts.get("info"), 1)
    }

    func testCloudLookupPaginatesAndDoesNotMatchAnUnrelatedHash() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" {
                let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!
                counts.increment("page")
                if offset == "0" { return .init((0..<100).map { self.summary(id: "UNRELATED\($0)", hash: String(repeating: "B", count: 40)) }) }
                XCTAssertEqual(offset, "100")
                return .init([self.summary()])
            }
            if request.url!.path.contains("/info/") {
                XCTAssertTrue(request.url!.path.hasSuffix("EXISTING")); return .init(self.info())
            }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(counts.get("page"), 2)
    }

    func testPendingCloudMatchWaitsWithoutResubmittingOrChangingSelection() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([self.summary(status: "downloading")]) }
            if request.url!.path.contains("/info/") {
                let call = counts.increment("info")
                return .init(self.info(status: call == 1 ? "downloading" : "downloaded", selected: [42]))
            }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link"), "Must not add or replace selected files")
            return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(counts.get("info"), 2)
    }

    func testDifferentExistingSelectionIsPreservedWhileNewEntryPrepares() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return .init([self.summary()]) }
            if path.hasSuffix("/info/EXISTING") { return .init(self.info(selected: [7])) }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"]) }
            if path.hasSuffix("/info/NEW") {
                return .init(self.info(id: "NEW", status: counts.get("selection") == 0 ? "waiting_files_selection" : "downloaded", selected: counts.get("selection") == 0 ? [] : [42]))
            }
            if path.contains("selectFiles") {
                XCTAssertTrue(path.hasSuffix("/NEW")); XCTAssertEqual(self.form(request)["files"], "42")
                counts.increment("selection"); return .init([:], status: 204)
            }
            XCTAssertTrue(path.hasSuffix("unrestrict/link")); return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(counts.get("add"), 1)
        XCTAssertEqual(counts.get("selection"), 1)
    }

    func testFilenameHintThroughTorrentioOverridesWrongIndexSafely() async throws {
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([self.summary()]) }
            if request.url!.path.contains("/info/") { return .init(self.info()) }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link"))
            XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/file42")
            return .init(self.playback)
        }
        let provider = BuiltInTorrentioProvider(session: URLProtocolStub.session())
        let source = SourceStream(title: "Fixture", providerName: provider.displayName, magnetURL: testInfoHash,
                                  fileIndex: 0, originalFileName: "second.mkv", providerId: provider.id)
        let stream = try await provider.resolve(source: source, using: client())
        XCTAssertEqual(stream.originalSource?.originalFileName, "second.mkv")
    }

    func testAddReturningExistingIdDoesNotReplaceOtherSelectedFiles() async throws {
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([self.summary()]) }
            if request.url!.path.contains("/info/") { return .init(self.info(selected: [7])) }
            if request.url!.path.hasSuffix("addMagnet") { return .init(["id": "EXISTING"]) }
            XCTFail("Existing other-file selection must not be changed or played")
            return .init([:], status: 500)
        }
        do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Expected unavailable file") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no unambiguous ready download link")) }
    }

    func testWaitingCloudEntryPreservesEveryPreviouslySelectedFile() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([self.summary(status: "waiting_files_selection")]) }
            if request.url!.path.contains("/info/") {
                return .init(self.info(status: counts.get("selected") == 0 ? "waiting_files_selection" : "downloaded"))
            }
            if request.url!.path.contains("selectFiles") {
                XCTAssertEqual(self.form(request)["files"], "7,42")
                counts.increment("selected"); return .init([:], status: 204)
            }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(counts.get("selected"), 1)
    }

    func testMissingOrAmbiguousFilenameDoesNotSilentlyUseTheIndex() throws {
        var json = info()
        var details = try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try details.requestedVideo(fileIndex: 0, fileName: "other-episode.mkv"))
        XCTAssertThrowsError(try details.requestedVideo(fileIndex: nil, fileName: nil), "Must not choose the largest episode in an unknown pack")
        json["files"] = [["id": 7, "path": "/a/episode.mkv", "bytes": 100, "selected": 1],
                         ["id": 42, "path": "/b/episode.mkv", "bytes": 200, "selected": 1]]
        details = try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try details.requestedVideo(fileIndex: 0, fileName: "episode.mkv"))
        XCTAssertEqual(try details.requestedVideo(fileIndex: 0, fileName: "b/episode.mkv").id, 42)
    }

    func testRejectionIdentifiesEachRequestStageWithoutRetriesOrLeakingSecrets() async throws {
        let stages: [(RealDebridOperation, String)] = [(.cloudLookup, "/rest/1.0/torrents"), (.addSource, "/rest/1.0/torrents/addMagnet"),
            (.torrentInfo, "/rest/1.0/torrents/info/NEW"), (.selectFile, "/rest/1.0/torrents/selectFiles/NEW"), (.playbackLink, "/rest/1.0/unrestrict/link")]
        for (operation, blockedPath) in stages {
            let counts = RequestCounts(), vault = KeychainService(isTesting: true)
            let production = client(keychain: vault)
            URLProtocolStub.configure { request in
                let path = request.url!.path
                if path == blockedPath {
                    counts.increment("blocked")
                    return .init(["error": "infringing_file private-token https://secret.invalid/?auth=secret", "error_code": 35], status: 451)
                }
                if path == "/rest/1.0/torrents" { return .init([]) }
                if path.hasSuffix("addMagnet") { return .init(["id": "NEW"]) }
                if path.contains("/info/") { return .init(self.info(id: "NEW", status: operation == .selectFile ? "waiting_files_selection" : "downloaded", selected: operation == .selectFile ? [] : [42])) }
                XCTFail("Unexpected request after refusal: \(path)"); return .init([:], status: 500)
            }
            do {
                _ = try await production.resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
                XCTFail("Expected a source rejection")
            } catch RealDebridError.requestFailed(let failure) {
                XCTAssertEqual(failure.operation, operation)
                XCTAssertEqual(failure.statusCode, 451); XCTAssertEqual(failure.code, 35)
                XCTAssertTrue(failure.localizedDescription.contains("Infringing file"))
                XCTAssertFalse((failure.localizedDescription + failure.diagnosticDetails).contains("private-token"))
                XCTAssertFalse(failure.diagnosticDetails.contains("secret.invalid"))
            }
            XCTAssertEqual(counts.get("blocked"), 1, "HTTP 451 must not trigger automatic retries")
            XCTAssertTrue(production.isAuthenticated)
            XCTAssertEqual(vault.get(key: .rdAccessToken), "private-token")
        }
    }

    func testCloudEntryRemovedBetweenListAndInfoDoesNotBreakOtherExactMatch() async throws {
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([self.summary(id: "STALE"), self.summary()]) }
            if request.url!.path.hasSuffix("/STALE") { return .init(["error_code": 7], status: 404) }
            if request.url!.path.contains("/info/") { return .init(self.info()) }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link")); return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
    }

    func testWrongHashAfterAddingNeverUnlocksOrPlaysAnotherTorrent() async throws {
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { return .init([]) }
            if request.url!.path.hasSuffix("addMagnet") { return .init(["id": "NEW"]) }
            if request.url!.path.contains("/info/") { return .init(self.info(id: "NEW", hash: String(repeating: "B", count: 40))) }
            XCTFail("Must not select/unrestrict a mismatched torrent"); return .init(self.playback)
        }
        do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Expected mismatch") }
        catch { XCTAssertTrue(error.localizedDescription.contains("different torrent")) }
    }

    func testLogoutDuringCloudLookupPreventsAddingOnAnotherAccount() async throws {
        let counts = RequestCounts(), production = client()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" { counts.increment("lookup"); return .init([], delay: 0.15) }
            counts.increment("unexpected"); return .init([:], status: 500)
        }
        let task = Task { try await production.resolveMagnetToStream(magnet: self.testInfoHash, preferredFileIndex: 1) }
        for _ in 0..<100 {
            if counts.get("lookup") > 0 { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(counts.get("lookup"), 1)
        production.logout()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(counts.get("unexpected"), 0)
    }


    func testMalformedCloudEntryDoesNotBlockOrdinarySourceResolution() async throws {
        let counts = RequestCounts()
        var bad = summary()
        bad["hash"] = true
        let encoded = try JSONSerialization.data(withJSONObject: [bad])
        // Reproduce the original failure: strict whole-array decoding aborts
        // on an unrelated field before any selected-source request is made.
        XCTAssertThrowsError(try JSONDecoder().decode([RDTorrent].self, from: encoded)) { error in
            guard case DecodingError.typeMismatch(_, let context) = error else { return XCTFail("Expected the original decoder failure") }
            XCTAssertEqual(context.codingPath.last?.stringValue, "hash")
        }
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { counts.increment("cloud"); return .init([bad]) }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"]) }
            if path.contains("/info/") { return .init(self.info(id: "NEW", selected: [42])) }
            XCTAssertTrue(path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
        XCTAssertEqual(counts.get("cloud"), 1)
        XCTAssertEqual(counts.get("add"), 1)
    }

    func testInvalidJSONInOptionalLookupDoesNotBlockSelectedSource() async throws {
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" {
                var reply = URLProtocolStub.Reply([:])
                reply.body = Data("<html>unexpected response</html>".utf8)
                return reply
            }
            if path.hasSuffix("addMagnet") { return .init(["id": "NEW"]) }
            if path.contains("/info/") { return .init(self.info(id: "NEW", selected: [42])) }
            XCTAssertTrue(path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
    }

    func testDetailDecoderFailureRetainsExactFieldAndNeverSelectsWrongFile() async throws {
        URLProtocolStub.configure { _ in
            var fixture = self.info()
            fixture["files"] = [["id": 42, "path": "/second.mkv", "bytes": 200, "selected": "private-response-value"]]
            return .init(fixture)
        }
        do { _ = try await client().getTorrentInfo(id: "EXISTING"); XCTFail("Expected typed decoder failure") }
        catch RealDebridError.responseDecodingFailed(let failure) {
            XCTAssertEqual(failure.operation, .torrentInfo)
            XCTAssertEqual(failure.codingPath, "$.files[0].selected")
            XCTAssertEqual(failure.reason, "Type mismatch")
            XCTAssertFalse((failure.localizedDescription + failure.diagnosticDetails).contains("private-response-value"))
            XCTAssertTrue(failure.diagnosticDetails.contains("Swift.Int"))
        }
    }

    func testPlaybackLinkDecoderFailureIdentifiesMissingDownloadWithoutRawResponse() async throws {
        URLProtocolStub.configure { _ in
            var fixture = self.playback
            fixture["filesize"] = "private-signed-url-or-token"
            fixture["download"] = NSNull()
            return .init(fixture)
        }
        do { _ = try await client().unrestrictLink("https://real-debrid.com/d/file42"); XCTFail("Expected typed decoder failure") }
        catch RealDebridError.responseDecodingFailed(let failure) {
            XCTAssertEqual(failure.operation, .playbackLink)
            XCTAssertEqual(failure.codingPath, "$.download")
            XCTAssertTrue(failure.diagnosticDetails.contains("Swift.String"))
            XCTAssertFalse(failure.diagnosticDetails.contains("private-signed-url-or-token"))
        }
    }

    func testSuccessfulHTTPStatusWithServiceRefusalIsNotAnOptionalLookupFailure() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" {
                return .init(["error": "infringing_file", "error_code": 35], status: 200)
            }
            counts.increment("unexpected")
            return .init(["id": "NEW"])
        }
        do { _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1); XCTFail("Expected service refusal") }
        catch RealDebridError.requestFailed(let failure) {
            XCTAssertEqual(failure.operation, .cloudLookup)
            XCTAssertEqual(failure.statusCode, 200)
            XCTAssertEqual(failure.code, 35)
        }
        XCTAssertEqual(counts.get("unexpected"), 0, "An explicit refusal must not fall back or add again")
    }

    func testUnreadableExistingEntryDoesNotBlockValidNewExactSource() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" { return .init([self.summary()]) }
            if path.hasSuffix("/info/EXISTING") {
                var fixture = self.info(); fixture["hash"] = NSNull()
                return .init(fixture)
            }
            if path.hasSuffix("addMagnet") { counts.increment("add"); return .init(["id": "NEW"]) }
            if path.hasSuffix("/info/NEW") { return .init(self.info(id: "NEW", selected: [42])) }
            XCTAssertTrue(path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        let stream = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(stream.filename, "second.mkv")
        XCTAssertEqual(counts.get("add"), 1)
    }

    func testMissingNullAndWrongTypeResponsesHaveDistinctRedactedDiagnostics() async throws {
        let cases: [(String, Any?, String)] = [("hash", nil, "Missing field"), ("hash", NSNull(), "Null value"), ("hash", false, "Type mismatch")]
        for (field, value, reason) in cases {
            URLProtocolStub.configure { _ in
                var fixture = self.info()
                if let value { fixture[field] = value } else { fixture.removeValue(forKey: field) }
                return .init(fixture)
            }
            do { _ = try await client().getTorrentInfo(id: "EXISTING"); XCTFail("Expected decoding error") }
            catch RealDebridError.responseDecodingFailed(let failure) {
                XCTAssertEqual(failure.operation, .torrentInfo)
                XCTAssertEqual(failure.codingPath, "$." + field)
                XCTAssertEqual(failure.reason, reason)
            }
        }
    }


    func testCloudMetadataNumbersAndNullTelemetryDoNotBlockReadyReuse() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            let path = request.url!.path
            if path == "/rest/1.0/torrents" {
                var entry = self.summary()
                entry["bytes"] = "300"; entry["progress"] = "100"; entry["split"] = "50"
                entry["host"] = NSNull(); entry["speed"] = "not available"; entry["seeders"] = NSNull()
                return .init([entry])
            }
            if path.contains("/info/") {
                var entry = self.info(selected: [42])
                entry["bytes"] = "300"; entry["progress"] = "100"; entry["host"] = NSNull()
                entry["files"] = [["id": "7", "path": "/first.mkv", "bytes": "100", "selected": false],
                                  ["id": "42", "path": "/second.mkv", "bytes": "200", "selected": "1"]]
                return .init(entry)
            }
            if path.hasSuffix("unrestrict/link") {
                XCTAssertEqual(self.form(request)["link"], "https://real-debrid.com/d/file42")
                var reply = self.playback; reply["filesize"] = "200"; reply["streamable"] = true
                reply["host"] = NSNull(); reply["mimeType"] = NSNull()
                return .init(reply)
            }
            counts.increment("unexpected"); return .init([:], status: 500)
        }
        let playable = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(playable.filename, "second.mkv")
        XCTAssertEqual(playable.fileSize, 200)
        XCTAssertEqual(counts.get("unexpected"), 0, "Recoverable metadata must not cause another magnet add")
    }

    func testCloudPageKeepsValidEntriesAndReportsInvalidIdentity() async throws {
        URLProtocolStub.configure { _ in
            var bad = self.summary(id: "BAD"); bad["id"] = NSNull()
            return .init([self.summary(), bad])
        }
        let page = try await client().getTorrentPage(offset: 0, limit: 100)
        XCTAssertEqual(page.items.map(\.id), ["EXISTING"])
        XCTAssertEqual(page.rawItemCount, 2)
        XCTAssertEqual(page.ignoredItemCount, 1)
        XCTAssertEqual(page.firstFailure?.codingPath, "$[1].id")
        XCTAssertNotNil(page.warningMessage)
        let listed = try await client().getTorrents(offset: 0, limit: 100)
        XCTAssertEqual(listed.count, 1)
    }

    func testPaginationUsesWireCountAfterIgnoringUnreadableEntry() async throws {
        let counts = RequestCounts()
        URLProtocolStub.configure { request in
            if request.url!.path == "/rest/1.0/torrents" {
                let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!
                counts.increment("page")
                if offset == "0" {
                    var entries = (0..<100).map { self.summary(id: "OTHER\($0)", hash: String(repeating: "B", count: 40)) }
                    entries[0]["id"] = NSNull()
                    return .init(entries)
                }
                XCTAssertEqual(offset, "100")
                return .init([self.summary()])
            }
            if request.url!.path.contains("/info/") { return .init(self.info(selected: [42])) }
            XCTAssertTrue(request.url!.path.hasSuffix("unrestrict/link"))
            return .init(self.playback)
        }
        _ = try await client().resolveMagnetToStream(magnet: testInfoHash, preferredFileIndex: 1)
        XCTAssertEqual(counts.get("page"), 2)
    }

    func testAllUnreadableCloudRowsAreReportedRatherThanAnEmptyAccount() async throws {
        URLProtocolStub.configure { _ in
            var entry = self.summary(); entry["hash"] = false
            return .init([entry])
        }
        let page = try await client().getTorrentPage(offset: 0, limit: 100)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.ignoredItemCount, 1)
        XCTAssertNotNil(page.firstFailure)
        do { _ = try await client().getTorrents(offset: 0, limit: 100); XCTFail("Must not claim an empty account") }
        catch RealDebridError.responseDecodingFailed(let failure) { XCTAssertEqual(failure.codingPath, "$[0].hash") }
    }

    func testFileIdsAndFlagsAreExactAndPlaybackURLsStayStrict() throws {
        var entry = info()
        entry["files"] = [["id": "42", "path": "/second.mkv", "bytes": NSNull(), "selected": true]]
        var decoded = try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: entry))
        XCTAssertEqual(decoded.files.first?.id, 42)
        XCTAssertTrue(decoded.files.first!.isSelected)
        let invalidIds: [Any] = ["42.5", 42.5, NSNull()]
        for invalid in invalidIds {
            entry["files"] = [["id": invalid, "path": "/second.mkv", "bytes": 200, "selected": 1]]
            XCTAssertThrowsError(try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: entry)))
        }
        entry["files"] = [["id": 42, "path": "/second.mkv", "bytes": 200, "selected": 2]]
        XCTAssertThrowsError(try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: entry)))
        var reply = playback; reply["download"] = "http://fixture.invalid/video.mkv"
        let unsafe = try JSONDecoder().decode(RDUnrestrictResponse.self, from: JSONSerialization.data(withJSONObject: reply))
        XCTAssertThrowsError(try RealDebridClient.playable(from: unsafe))
        decoded = try JSONDecoder().decode(RDTorrentInfo.self, from: JSONSerialization.data(withJSONObject: info()))
        XCTAssertEqual(try decoded.requestedVideo(fileIndex: 1, fileName: nil).id, 42)
    }

    func testOptionalPresentationFieldsDoNotInventReadyStatusOrSourceIdentity() throws {
        var entry = summary(status: "magnet_conversion")
        for key in ["filename", "bytes", "host", "progress", "added", "links"] { entry[key] = NSNull() }
        entry["split"] = []; entry["speed"] = "unknown"; entry["seeders"] = false
        let torrent = try JSONDecoder().decode(RDTorrent.self, from: JSONSerialization.data(withJSONObject: entry))
        XCTAssertEqual(torrent.formattedSize, "Unknown size")
        XCTAssertFalse(torrent.isReadyToStream)
        XCTAssertEqual(torrent.hash, testInfoHash.lowercased())
        XCTAssertNil(torrent.speed)
        entry["id"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(RDTorrent.self, from: JSONSerialization.data(withJSONObject: entry)))
    }

    func testDirectProviderURLDoesNotResubmitTheAlsoSuppliedMagnet() async throws {
        URLProtocolStub.configure { _ in XCTFail("Direct playback must not call the debrid API"); return .init([:], status: 500) }
        let provider = BuiltInTorrentioProvider()
        let url = URL(string: "https://fixture.invalid/resolved.mkv")!
        let source = SourceStream(title: "Fixture", providerName: provider.displayName, magnetURL: testInfoHash, providerId: provider.id, directURL: url)
        let stream = try await provider.resolve(source: source, using: client())
        XCTAssertEqual(stream.streamURL, url)
    }
}
