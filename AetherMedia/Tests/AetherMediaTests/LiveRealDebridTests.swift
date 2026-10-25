#if canImport(UIKit)
import XCTest
import UIKit
import AVFoundation
import CoreFoundation
@testable import AetherMedia

/// Observe actual HTTP transport without intercepting or substituting any response.
/// Endpoint templates deliberately omit query strings and account/torrent identifiers.
private final class LiveHTTPObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [[String: Any]] = []
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last,
              let response = transaction.response as? HTTPURLResponse,
              response.url?.host == "api.real-debrid.com" else { return }
        let path = response.url?.path ?? ""
        let known: Set<String> = ["/oauth/v2/device/code", "/oauth/v2/device/credentials", "/oauth/v2/token",
                                  "/rest/1.0/user", "/rest/1.0/torrents", "/rest/1.0/torrents/addMagnet",
                                  "/rest/1.0/unrestrict/link", "/rest/1.0/disable_access_token"]
        let template: String
        if known.contains(path) { template = path }
        else if path.hasPrefix("/rest/1.0/torrents/info/") { template = "/rest/1.0/torrents/info/{id}" }
        else if path.hasPrefix("/rest/1.0/torrents/selectFiles/") { template = "/rest/1.0/torrents/selectFiles/{id}" }
        else if path.hasPrefix("/rest/1.0/torrents/delete/") { template = "/rest/1.0/torrents/delete/{id}" }
        else { template = "other" }
        lock.lock(); defer { lock.unlock() }
        if observations.count < 512 {
            observations.append(["endpoint": template, "method": transaction.request.httpMethod ?? "unknown",
                                 "http_status": response.statusCode, "response_bytes": task.countOfBytesReceived])
        }
    }
    func snapshot() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return observations }
}

/// Opt-in network integration. No MockRealDebridClient, URLProtocol, or fixture responses.
/// Credentials remain in this process's memory; only the pending device grant is a private file.
@MainActor
final class LiveRealDebridTests: XCTestCase {
    // Match SourceStream.extractHash's canonical uppercase representation.
    private let demoHash = "DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C"
    private let demoMagnet = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.torrent"
    private struct Grant: Codable { let device: RDDeviceCodeResponse; let requestedAt: Date }
    private enum TestFailure: Error { case failed, approvalExpired, unsafeState }

    func testPublicFixtureUsesTheProductionHashNormalization() {
        XCTAssertEqual(SourceStream.extractHash(from: demoMagnet), demoHash)
        XCTAssertEqual(SourceStream.extractHash(from: demoHash.lowercased()), demoHash)
        XCTAssertEqual(SourceStream.extractHash(from: demoHash), demoHash)
    }

    private func settings() throws -> (grant: URL, publicCode: URL, report: URL) {
        let e = ProcessInfo.processInfo.environment
        guard e["AETHER_LIVE_RD"] == "1" else { throw XCTSkip("Live account integration is explicitly opt-in.") }
        guard let grant = e["AETHER_LIVE_GRANT_PATH"], let publicCode = e["AETHER_LIVE_PUBLIC_CODE_PATH"],
              let report = e["AETHER_LIVE_REPORT_PATH"] else { throw TestFailure.unsafeState }
        return (URL(fileURLWithPath: grant), URL(fileURLWithPath: publicCode), URL(fileURLWithPath: report))
    }
    private func session(observer: LiveHTTPObserver? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: observer, delegateQueue: nil)
    }
    private func write(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func test00RequestAuthorization() async throws {
        let paths = try settings(), transport = session()
        defer { transport.invalidateAndCancel() }
        // isTesting changes credential STORAGE only. The HTTP transport is a real ephemeral URLSession.
        let client = RealDebridClient(session: transport, keychain: KeychainService(isTesting: true))
        do {
            guard SourceStream.extractHash(from: demoMagnet) == demoHash else { throw TestFailure.unsafeState }
            let device = try await client.requestDeviceCode()
            guard URL(string: device.verificationUrl)?.host == "real-debrid.com", device.expiresIn > 0,
                  !device.deviceCode.isEmpty, !device.userCode.isEmpty else { throw TestFailure.unsafeState }
            let now = Date()
            let grant = Grant(device: device, requestedAt: now)
            try FileManager.default.createDirectory(at: paths.grant.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(grant).write(to: paths.grant, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.grant.path)
            try write(["status": "awaiting_approval", "verification_url": device.verificationUrl,
                       "user_code": device.userCode, "expires_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(device.expiresIn))),
                       "approval_wait_seconds": min(1200, device.expiresIn), "real_network": true], to: paths.publicCode)
        } catch {
            try? write(["status": "device_code_request_failed", "real_network": true,
                        "error": diagnostic(error)], to: paths.report)
            XCTFail("Live device-code request failed; inspect the sanitized report.")
        }
    }

    func test10LiveAccountCloudAndPublicVideo() async throws {
        let paths = try settings()
        let grant = try JSONDecoder().decode(Grant.self, from: Data(contentsOf: paths.grant))
        let observer = LiveHTTPObserver()
        let transport = session(observer: observer), vault = KeychainService(isTesting: true)
        let client = RealDebridClient(session: transport, keychain: vault)
        var events: [[String: Any]] = [], ownedTorrent: String?, hadFailure = false
        func record(_ stage: String, _ status: String, _ extra: [String: Any] = [:]) {
            events.append(extra.merging(["stage": stage, "status": status]) { _, rhs in rhs })
            if status == "failed" { hadFailure = true }
            try? write(["status": "running", "real_network": true, "simulated_responses": false,
                        "http_requests": observer.snapshot(), "events": events], to: paths.report)
        }
        func fail(_ stage: String, _ error: Error) { record(stage, "failed", ["error": diagnostic(error)]) }
        defer { client.logout(); transport.invalidateAndCancel(); try? FileManager.default.removeItem(at: paths.grant) }

        do {
            record("authorization", "waiting_for_device_approval")
            let deadline = min(grant.requestedAt.addingTimeInterval(Double(grant.device.expiresIn)), Date().addingTimeInterval(1200))
            var credentials: RDCredentialsResponse?
            while Date() < deadline {
                do { credentials = try await client.pollForCredentials(deviceCode: grant.device.deviceCode); break }
                catch RealDebridError.deviceAuthPending {
                    try await Task.sleep(nanoseconds: UInt64(max(5, grant.device.interval)) * 1_000_000_000)
                }
            }
            guard let credentials else { throw TestFailure.approvalExpired }
            _ = try await client.exchangeCodeForToken(clientId: credentials.clientId, clientSecret: credentials.clientSecret,
                                                     deviceCode: grant.device.deviceCode)
            record("authorization", "passed")
            do {
                let profile = try await client.getUserProfile()
                record("account_profile", "passed", ["is_premium": profile.isPremium])
            } catch {
                fail("account_profile", error)
                record("account_wire_shape", "observed", await schema(path: "user", query: [], vault: vault, transport: transport))
            }

            var cloud: [RDTorrent] = [], complete = false, unreadable = 0
            for pageNumber in 0..<25 {
                let offset = pageNumber * 100
                do {
                    let page = try await client.getTorrentPage(offset: offset, limit: 100)
                    cloud.append(contentsOf: page.items); unreadable += page.ignoredItemCount
                    record("cloud_page", page.ignoredItemCount == 0 ? "passed" : "failed",
                           ["page": pageNumber, "raw_count": page.rawItemCount, "readable_count": page.items.count,
                            "ignored_count": page.ignoredItemCount,
                            "first_failure": page.firstFailure?.diagnosticDetails ?? "none"])
                    if page.ignoredItemCount > 0 {
                        record("cloud_wire_shape", "observed", await schema(path: "torrents", query: [
                            URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: "100")
                        ], vault: vault, transport: transport))
                    }
                    if page.rawItemCount < 100 { complete = true; break }
                } catch {
                    fail("cloud_page", error)
                    record("cloud_wire_shape", "observed", await schema(path: "torrents", query: [
                        URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: "100")
                    ], vault: vault, transport: transport)); break
                }
            }

            // Read existing cloud metadata and resolve one already-selected file. Never change its selections.
            var checkedExisting = false
            for torrent in cloud.filter(\.isReadyToStream).prefix(3) {
                do {
                    let info = try await client.getTorrentInfo(id: torrent.id)
                    guard SourceStream.extractHash(from: info.hash) == SourceStream.extractHash(from: torrent.hash),
                          let file = info.files.first(where: { $0.isVideo && $0.isSelected }) else { continue }
                    let link = try info.link(forFileId: file.id)
                    let unrestricted = try await client.unrestrictLink(link)
                    _ = try RealDebridClient.playable(from: unrestricted)
                    record("existing_cloud_file_and_link", "passed"); checkedExisting = true; break
                } catch { fail("existing_cloud_file_and_link", error) }
            }
            if !checkedExisting { record("existing_cloud_file_and_link", "not_verified") }

            // Public Creative Commons test torrent, from https://webtorrent.io/free-torrents.
            // Only create a test entry when the full pre-existing cloud list was readable.
            guard complete && unreadable == 0 else {
                record("public_video", "not_verified", ["reason": "Cloud inventory incomplete; no test torrent was added."])
                throw TestFailure.failed
            }
            let existingDemo = cloud.first { SourceStream.extractHash(from: $0.hash) == demoHash }
            let torrentId: String
            if let existingDemo { torrentId = existingDemo.id; record("public_torrent", "reused_existing") }
            else {
                torrentId = try await client.addMagnet(demoMagnet)
                ownedTorrent = torrentId
                record("public_add_magnet", "passed")
            }
            var ready: RDTorrentInfo?
            for attempt in 0..<90 {
                let info: RDTorrentInfo
                if attempt == 0 && ownedTorrent != nil { info = try await client.getNewTorrentInfo(id: torrentId) }
                else { info = try await client.getTorrentInfo(id: torrentId) }
                guard SourceStream.extractHash(from: info.hash) == demoHash else { throw TestFailure.unsafeState }
                if attempt == 0 { record("public_first_detail", "passed") }
                if ["error", "dead", "virus", "magnet_error"].contains(info.status) {
                    record("public_torrent_preparation", "failed", ["reason": "The service reported a terminal torrent state."])
                    throw TestFailure.failed
                }
                if !info.files.isEmpty {
                    let file = try info.requestedVideo(fileIndex: nil, fileName: nil)
                    if info.isAwaitingFileSelection && ownedTorrent != nil {
                        try await client.selectFiles(torrentId: torrentId, fileIds: [file.id])
                    } else if info.isReadyToStream && file.isSelected { ready = info; break }
                    else if existingDemo != nil && !file.isSelected {
                        record("public_video", "not_verified", ["reason": "Existing public torrent selections preserved."])
                        throw TestFailure.failed
                    }
                }
                if attempt < 89 { try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
            guard let ready else {
                record("public_torrent_preparation", "failed", ["reason": "No ready file within the three-minute preparation limit."])
                throw TestFailure.failed
            }
            record("public_torrent_preparation", "passed")
            let file = try ready.requestedVideo(fileIndex: nil, fileName: nil)
            let unrestricted = try await client.unrestrictLink(ready.link(forFileId: file.id))
            let playable = try RealDebridClient.playable(from: unrestricted)
            record("public_unrestrict", "passed")
            try await verifyPublicPlayback(playable, record: record)
        } catch {
            fail("live_pipeline", error)
            if let ownedTorrent, let page = try? await client.getTorrentPage(offset: 0, limit: 100) {
                let row = page.items.first { $0.id == ownedTorrent }
                let states: Set<String> = ["magnet_conversion", "waiting_files_selection", "queued", "downloading", "downloaded", "compressing", "uploading", "magnet_error", "error", "dead", "virus"]
                record("public_inventory_after_failure", "observed",
                       ["entry_visible": row != nil,
                        "expected_hash_matches": row.flatMap { SourceStream.extractHash(from: $0.hash) } == demoHash,
                        "torrent_state": row.flatMap { states.contains($0.status) ? $0.status : nil } ?? "not_available"])
            }
        }

        if let id = ownedTorrent {
            do { try await client.deleteTorrent(id: id); record("remove_test_torrent_only", "passed") }
            catch { fail("remove_test_torrent_only", error) }
        }
        // Disable only this newly authorized access token, never the phone or Kodi device grant.
        if let token = vault.get(key: .rdAccessToken) {
            var request = URLRequest(url: URL(string: "https://api.real-debrid.com/rest/1.0/disable_access_token")!)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.timeoutInterval = 20
            do {
                let (_, response) = try await transport.data(for: request)
                record("disable_test_access_token", (response as? HTTPURLResponse)?.statusCode == 204 ? "passed" : "failed")
            } catch { fail("disable_test_access_token", error) }
        }
        try write(["status": hadFailure ? "failed" : "passed", "real_network": true, "simulated_responses": false,
                   "test_scope": "Live iOS API and player integration; not a full UI tap-through or physical-iPhone test.",
                   "http_requests": observer.snapshot(), "events": events], to: paths.report)
        XCTAssertFalse(hadFailure, "Live integration encountered a failure; inspect the sanitized report.")
    }

    private func verifyPublicPlayback(_ stream: PlayableStream,
                                     record: (String, String, [String: Any]) -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = PlaybackEngine(persistence: PersistenceService(customStorageDirectory: directory))
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { throw TestFailure.failed }
        let window = UIWindow(windowScene: scene), host = UIViewController()
        host.view.backgroundColor = .black; window.rootViewController = host; window.makeKeyAndVisible()
        defer { engine.cleanupPlayer(); window.isHidden = true; try? FileManager.default.removeItem(at: directory) }
        engine.loadAndPlay(stream: stream, mediaItem: MediaItem(id: "live-public-video", title: "Big Buck Bunny"))
        var nativeLayer: AVPlayerLayer?, decoded = false, seconds: Double = 0
        for _ in 0..<450 {
            if let extended = engine.extendedController {
                if extended.videoView.superview == nil {
                    extended.videoView.frame = host.view.bounds; host.view.addSubview(extended.videoView)
                }
                seconds = extended.currentSeconds
                decoded = extended.hasVideoOutput && seconds > 1
            } else if let player = engine.player {
                if nativeLayer == nil {
                    let layer = AVPlayerLayer(player: player); layer.frame = host.view.bounds
                    host.view.layer.addSublayer(layer); nativeLayer = layer
                }
                seconds = player.currentTime().seconds
                decoded = nativeLayer?.isReadyForDisplay == true && seconds.isFinite && seconds > 1
            }
            if decoded { break }
            if case .failed = engine.state { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        record("public_video_output", decoded ? "passed" : "failed",
               ["time_advancing": decoded, "player": engine.extendedController == nil ? "AVPlayer" : "VLCKit"])
        guard decoded else { throw TestFailure.failed }
        engine.pause()
        record("public_video_pause", engine.state == .paused ? "passed" : "failed", [:])
    }

    /// Only known field names and JSON types. Never filenames, URLs, IDs, hashes, credentials, or response text.
    private func schema(path: String, query: [URLQueryItem], vault: KeychainService, transport: URLSession) async -> [String: Any] {
        guard let token = vault.get(key: .rdAccessToken) else { return ["observation": "not_authorized"] }
        var url = URLComponents(string: "https://api.real-debrid.com/rest/1.0/" + path)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await transport.data(for: request)
            var types: [String: Set<String>] = [:]
            if let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { collectTypes(value, path: "$", depth: 0, into: &types) }
            return ["http_status": (response as? HTTPURLResponse)?.statusCode ?? 0, "response_bytes": data.count,
                    "field_types": types.mapValues { $0.sorted() }]
        } catch { return ["error": diagnostic(error)] }
    }
    private func collectTypes(_ value: Any, path: String, depth: Int, into types: inout [String: Set<String>]) {
        guard depth <= 5 else { return }
        let allowed: Set<String> = ["id", "filename", "original_filename", "hash", "bytes", "original_bytes", "host", "split", "progress", "status", "added", "links", "ended", "speed", "seeders", "files", "path", "selected", "username", "email", "points", "type", "expiration", "error", "error_code", "download", "mimeType", "filesize", "chunks", "streamable"]
        if value is NSNull { types[path, default: []].insert("null") }
        else if let value = value as? [String: Any] {
            types[path, default: []].insert(value.isEmpty ? "empty_object" : "object")
            for (key, child) in value where allowed.contains(key) { collectTypes(child, path: path + "." + key, depth: depth + 1, into: &types) }
        } else if let value = value as? [Any] {
            types[path, default: []].insert(value.isEmpty ? "empty_array" : "array")
            for child in value.prefix(100) { collectTypes(child, path: path + "[]", depth: depth + 1, into: &types) }
        } else if value is String { types[path, default: []].insert("string") }
        else if let value = value as? NSNumber { types[path, default: []].insert(CFGetTypeID(value) == CFBooleanGetTypeID() ? "boolean" : "number") }
        else { types[path, default: []].insert("other") }
    }
    private func diagnostic(_ error: Error) -> [String: Any] {
        if let rd = error as? RealDebridError {
            switch rd {
            case .requestFailed(let failure): return ["category": "service_error", "details": failure.diagnosticDetails]
            case .responseDecodingFailed(let failure): return ["category": "decoding_error", "details": failure.diagnosticDetails]
            case .serviceError(let status, let code): return ["category": "service_error", "http_status": status, "service_code": code ?? -1]
            case .notAuthorized: return ["category": "not_authorized"]
            case .accountNotPremium: return ["category": "not_premium"]
            case .deviceAuthExpired: return ["category": "authorization_expired"]
            case .deviceAuthPending: return ["category": "authorization_pending"]
            case .rateLimited: return ["category": "rate_limited"]
            default: return ["category": "client_error"]
            }
        }
        if let failure = error as? TestFailure {
            switch failure {
            case .approvalExpired: return ["category": "approval_not_completed_in_time"]
            case .unsafeState: return ["category": "identity_or_configuration_check_failed"]
            case .failed: return ["category": "previous_stage_failed_or_unverified"]
            }
        }
        return ["category": "transport_or_system_error", "code": (error as NSError).code]
    }
}
#endif
