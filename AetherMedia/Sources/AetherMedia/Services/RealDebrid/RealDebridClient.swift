import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RealDebridError: LocalizedError, Sendable {
    case notAuthorized, accountNotPremium, deviceAuthExpired, deviceAuthPending, torrentNotFound
    case rateLimited(retryAfter: Int?)
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case serviceError(statusCode: Int, code: Int?)
    case requestFailed(RealDebridRequestFailure)
    case responseDecodingFailed(RealDebridDecodingFailure)
    case debridLinkResolutionFailed(String)
    case magnetAdditionFailed(String)
    case credentialStorageFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Connect or re-authorize your Real-Debrid account in Settings."
        case .accountNotPremium: return "This operation requires an active Real-Debrid Premium subscription."
        case .deviceAuthExpired: return "The authorization code expired. Request a new code."
        case .deviceAuthPending: return "Waiting for approval at real-debrid.com/device."
        case .torrentNotFound: return "The torrent is no longer in your Real-Debrid cloud."
        case .rateLimited(let seconds): return "Real-Debrid is rate limiting requests. Retry in \(seconds ?? 5) seconds."
        case .networkError(let message), .debridLinkResolutionFailed(let message), .magnetAdditionFailed(let message): return message
        case .invalidResponse(let status): return "Real-Debrid returned HTTP \(status)."
        case .serviceError(let status, let code): return "Real-Debrid rejected the request (HTTP \(status)\(code.map { ", code \($0)" } ?? ""))."
        case .requestFailed(let failure): return failure.errorDescription
        case .responseDecodingFailed(let failure): return failure.errorDescription
        case .credentialStorageFailed: return "Credentials could not be saved securely. Unlock the iPhone and retry authorization."
        }
    }

    public var diagnosticDetails: String? {
        switch self {
        case .requestFailed(let failure): return failure.diagnosticDetails
        case .responseDecodingFailed(let failure): return failure.diagnosticDetails
        case .serviceError(let status, let code):
            return "HTTP: \(status)\nReal-Debrid code: \(code.map(String.init) ?? "not supplied")"
        default: return nil
        }
    }
}


public struct RealDebridCloudPage: Sendable {
    public let items: [RDTorrent]
    public let rawItemCount: Int
    public let ignoredItemCount: Int
    public let firstFailure: RealDebridDecodingFailure?
    public init(items: [RDTorrent], rawItemCount: Int, ignoredItemCount: Int = 0, firstFailure: RealDebridDecodingFailure? = nil) {
        self.items = items; self.rawItemCount = rawItemCount
        self.ignoredItemCount = ignoredItemCount; self.firstFailure = firstFailure
    }
    public var warningMessage: String? {
        guard ignoredItemCount > 0 else { return nil }
        return "\(ignoredItemCount) cloud entries could not be read. Showing \(items.count) readable entries."
    }
}

private struct RDTorrentBatch: Decodable {
    let page: RealDebridCloudPage
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var items: [RDTorrent] = []
        var count = 0, ignored = 0
        var first: RealDebridDecodingFailure?
        while !c.isAtEnd {
            let itemDecoder = try c.superDecoder()
            count += 1
            do { items.append(try RDTorrent(from: itemDecoder)) }
            catch let error as DecodingError {
                ignored += 1
                if first == nil { first = RealDebridDecodingFailure(operation: .cloudLookup, error: error) }
            }
        }
        page = RealDebridCloudPage(items: items, rawItemCount: count, ignoredItemCount: ignored, firstFailure: first)
    }
}

public protocol RealDebridClientProtocol: Sendable {
    var isAuthenticated: Bool { get }
    func requestDeviceCode() async throws -> RDDeviceCodeResponse
    func pollForCredentials(deviceCode: String) async throws -> RDCredentialsResponse
    func exchangeCodeForToken(clientId: String, clientSecret: String, deviceCode: String) async throws -> RDTokenResponse
    func refreshToken() async throws
    func getUserProfile() async throws -> RDUser
    func logout()
    func getTorrents(offset: Int, limit: Int) async throws -> [RDTorrent]
    func getTorrentPage(offset: Int, limit: Int) async throws -> RealDebridCloudPage
    func getTorrentInfo(id: String) async throws -> RDTorrentInfo
    func addMagnet(_ magnet: String) async throws -> String
    func selectFiles(torrentId: String, fileIds: [Int]?) async throws
    func checkInstantAvailability(hashes: [String]) async throws -> [String: RDInstantAvailability]
    func deleteTorrent(id: String) async throws
    func unrestrictLink(_ link: String) async throws -> RDUnrestrictResponse
    /// preferredFileIndex is a zero-based torrent file offset, not a Real-Debrid file ID.
    func resolveMagnetToStream(magnet: String, preferredFileIndex: Int?) async throws -> PlayableStream
    func resolveMagnetToStream(magnet: String, preferredFileIndex: Int?, preferredFileName: String?) async throws -> PlayableStream
}

public extension RealDebridClientProtocol {
    func getTorrentPage(offset: Int, limit: Int) async throws -> RealDebridCloudPage {
        let items = try await getTorrents(offset: offset, limit: limit)
        return RealDebridCloudPage(items: items, rawItemCount: items.count)
    }

    /// Compatibility for clients that do not implement filename-aware resolution.
    func resolveMagnetToStream(magnet: String, preferredFileIndex: Int?, preferredFileName: String?) async throws -> PlayableStream {
        try await resolveMagnetToStream(magnet: magnet, preferredFileIndex: preferredFileIndex)
    }
}

public final class RealDebridClient: RealDebridClientProtocol, @unchecked Sendable {
    public static let shared = RealDebridClient()
    public static let defaultClientId = "X245A4XAIBGVM"
    private let baseURL = URL(string: "https://api.real-debrid.com/rest/1.0")!
    private let oauthURL = URL(string: "https://api.real-debrid.com/oauth/v2")!
    private let session: URLSession
    private let keychain: KeychainService
    private let authLock = NSLock()
    private var authGeneration = 0
    private var inFlightRefresh: (id: UUID, task: Task<Void, Error>)?
    private let pollIntervalNanoseconds: UInt64
    private let maxPreparationAttempts: Int
    private let grantType = "http://oauth.net/grant_type/device/1.0"

    public init(session: URLSession = .shared, keychain: KeychainService = .shared,
                pollIntervalNanoseconds: UInt64 = 1_000_000_000, maxPreparationAttempts: Int = 60) {
        self.session = session
        self.keychain = keychain
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPreparationAttempts = max(1, maxPreparationAttempts)
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        authLock.lock()
        defer { authLock.unlock() }
        return try body()
    }
    public var isAuthenticated: Bool { locked { keychain.get(key: .rdAccessToken) != nil } }

    private func formBody(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return values.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)!
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw RealDebridError.networkError("Invalid response from Real-Debrid.")
        }
        return (data, http)
    }

    private func responseError(_ data: Data, _ http: HTTPURLResponse, operation: RealDebridOperation = .authorization) -> RealDebridError {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_code"] as? Int
        if code == 20 { return .accountNotPremium }
        if http.statusCode == 401 { return .notAuthorized }
        if http.statusCode == 429 { return .rateLimited(retryAfter: retryDelay(http)) }
        return .requestFailed(RealDebridRequestFailure(operation: operation, statusCode: http.statusCode, code: code))
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, operation: RealDebridOperation) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as DecodingError {
            throw RealDebridError.responseDecodingFailed(RealDebridDecodingFailure(operation: operation, error: error))
        }
    }

    private func retryDelay(_ response: HTTPURLResponse) -> Int {
        max(0, Int(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5)
    }

    public func requestDeviceCode() async throws -> RDDeviceCodeResponse {
        var url = URLComponents(url: oauthURL.appendingPathComponent("device/code"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: Self.defaultClientId), URLQueryItem(name: "new_credentials", value: "yes")]
        let (data, response) = try await send(URLRequest(url: url.url!))
        guard (200...299).contains(response.statusCode) else { throw responseError(data, response) }
        return try decode(RDDeviceCodeResponse.self, data: data, operation: .authorization)
    }

    public func pollForCredentials(deviceCode: String) async throws -> RDCredentialsResponse {
        var url = URLComponents(url: oauthURL.appendingPathComponent("device/credentials"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: Self.defaultClientId), URLQueryItem(name: "code", value: deviceCode)]
        let (data, response) = try await send(URLRequest(url: url.url!))
        switch response.statusCode {
        case 200: return try decode(RDCredentialsResponse.self, data: data, operation: .authorization)
        case 400, 403: throw RealDebridError.deviceAuthPending
        case 404, 410: throw RealDebridError.deviceAuthExpired
        default: throw responseError(data, response)
        }
    }

    private func obtainToken(clientId: String, clientSecret: String, code: String) async throws -> RDTokenResponse {
        var request = URLRequest(url: oauthURL.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientId, "client_secret": clientSecret, "code": code, "grant_type": grantType])
        let (data, response) = try await send(request)
        guard (200...299).contains(response.statusCode) else { throw responseError(data, response) }
        return try decode(RDTokenResponse.self, data: data, operation: .authorization)
    }

    public func exchangeCodeForToken(clientId: String, clientSecret: String, deviceCode: String) async throws -> RDTokenResponse {
        let generation = locked { authGeneration }
        let token = try await obtainToken(clientId: clientId, clientSecret: clientSecret, code: deviceCode)
        try Task.checkCancellation()
        try locked {
            guard generation == authGeneration else { throw CancellationError() }
            guard let refresh = token.refreshToken,
                  keychain.save(key: .rdClientId, value: clientId),
                  keychain.save(key: .rdClientSecret, value: clientSecret),
                  keychain.save(key: .rdRefreshToken, value: refresh),
                  keychain.save(key: .rdAccessToken, value: token.accessToken) else {
                keychain.clearAll()
                throw RealDebridError.credentialStorageFailed
            }
            authGeneration += 1
            inFlightRefresh?.task.cancel()
            inFlightRefresh = nil
        }
        return token
    }

    public func refreshToken() async throws { try await refresh(rejectedToken: nil) }

    private func refresh(rejectedToken: String?) async throws {
        let task: Task<Void, Error>? = locked {
            // Another request may already have refreshed the rejected access token.
            if let rejectedToken, let current = keychain.get(key: .rdAccessToken), current != rejectedToken { return nil }
            if let existing = inFlightRefresh { return existing.task }
            let id = UUID()
            let generation = authGeneration
            let task = Task<Void, Error> { [self] in
                defer { finishRefresh(id: id) }
                guard let refreshToken = keychain.get(key: .rdRefreshToken),
                      let clientId = keychain.get(key: .rdClientId),
                      let secret = keychain.get(key: .rdClientSecret) else { throw RealDebridError.notAuthorized }
                let token = try await obtainToken(clientId: clientId, clientSecret: secret, code: refreshToken)
                try Task.checkCancellation()
                try locked {
                    guard generation == authGeneration else { throw CancellationError() }
                    if let refresh = token.refreshToken, !keychain.save(key: .rdRefreshToken, value: refresh) {
                        throw RealDebridError.credentialStorageFailed
                    }
                    guard keychain.save(key: .rdAccessToken, value: token.accessToken) else { throw RealDebridError.credentialStorageFailed }
                }
            }
            inFlightRefresh = (id, task)
            return task
        }
        try await task?.value
    }

    private func finishRefresh(id: UUID) {
        locked { if inFlightRefresh?.id == id { inFlightRefresh = nil } }
    }
    public func logout() {
        locked {
            authGeneration += 1
            inFlightRefresh?.task.cancel()
            inFlightRefresh = nil
            keychain.clearAll()
        }
    }

    private func authorizedRequest(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil,
                                   emptyCollectionOnNoContent: Bool = false,
                                   didRefresh: Bool = false, rateAttempts: Int = 0) async throws -> Data {
        let snapshot = locked { (keychain.get(key: .rdAccessToken), authGeneration) }
        guard let token = snapshot.0 else { throw RealDebridError.notAuthorized }
        var url = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await send(request)
        guard locked({ authGeneration == snapshot.1 }) else { throw CancellationError() }
        if response.statusCode == 401 && !didRefresh {
            try await refresh(rejectedToken: token)
            return try await authorizedRequest(path: path, query: query, method: method, body: body,
                                               emptyCollectionOnNoContent: emptyCollectionOnNoContent,
                                               didRefresh: true, rateAttempts: rateAttempts)
        }
        if response.statusCode == 429 {
            let delay = retryDelay(response)
            guard rateAttempts < 2, delay <= 30 else { throw RealDebridError.rateLimited(retryAfter: delay) }
            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            return try await authorizedRequest(path: path, query: query, method: method, body: body,
                                               emptyCollectionOnNoContent: emptyCollectionOnNoContent,
                                               didRefresh: didRefresh, rateAttempts: rateAttempts + 1)
        }
        guard (200...299).contains(response.statusCode) else { throw responseError(data, response, operation: .forPath(path)) }
        // A service error envelope must never be mistaken for corrupt optional
        // cloud metadata and retried through a new add request.
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let message = object["error"] as? String, !message.isEmpty {
            throw responseError(data, response, operation: .forPath(path))
        }
        // The live API returns 204 with zero bytes for an empty cloud page.
        // Normalize only that explicit list response; empty 200 bodies and
        // missing detail/token/link responses must still fail validation.
        if emptyCollectionOnNoContent && response.statusCode == 204 && data.isEmpty {
            return Data("[]".utf8)
        }
        return data
    }

    public func getUserProfile() async throws -> RDUser {
        try decode(RDUser.self, data: await authorizedRequest(path: "user"), operation: .account)
    }
    public func getTorrents(offset: Int = 0, limit: Int = 50) async throws -> [RDTorrent] {
        let page = try await getTorrentPage(offset: offset, limit: limit)
        if page.items.isEmpty, let failure = page.firstFailure {
            throw RealDebridError.responseDecodingFailed(failure)
        }
        return page.items
    }
    public func getTorrentPage(offset: Int = 0, limit: Int = 50) async throws -> RealDebridCloudPage {
        let data = try await authorizedRequest(path: "torrents", query: [
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "limit", value: String(min(max(1, limit), 2500)))
        ], emptyCollectionOnNoContent: true)
        return try decode(RDTorrentBatch.self, data: data, operation: .cloudLookup).page
    }
    public func getTorrentInfo(id: String) async throws -> RDTorrentInfo {
        try decode(RDTorrentInfo.self, data: await authorizedRequest(path: "torrents/info/\(id)"), operation: .torrentInfo)
    }

    /// Only for the first inspection after a successful add. A just-created
    /// entry may not be visible yet; never resubmit it or relax its identity.
    func getNewTorrentInfo(id: String) async throws -> RDTorrentInfo {
        let generation = locked { authGeneration }
        let attempts = min(6, maxPreparationAttempts)
        for attempt in 0..<attempts {
            try requireAccount(generation)
            do {
                let info = try await getTorrentInfo(id: id)
                try requireAccount(generation)
                return info
            } catch RealDebridError.requestFailed(let failure)
                where failure.operation == .torrentInfo && failure.statusCode == 404 && failure.code == 7 && attempt + 1 < attempts {
                try requireAccount(generation)
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
        throw RealDebridError.torrentNotFound
    }
    public func addMagnet(_ magnet: String) async throws -> String {
        guard let normalized = SourceStream.normalizedMagnet(magnet) else { throw RealDebridError.magnetAdditionFailed("Enter a valid v1 magnet link or SHA1 info-hash.") }
        let data = try await authorizedRequest(path: "torrents/addMagnet", method: "POST", body: formBody(["magnet": normalized]))
        return try decode(RDAddMagnetResponse.self, data: data, operation: .addSource).id
    }
    public func selectFiles(torrentId: String, fileIds: [Int]?) async throws {
        let selection = fileIds.map { $0.map(String.init).joined(separator: ",") } ?? "all"
        guard !selection.isEmpty else { throw RealDebridError.debridLinkResolutionFailed("No files selected.") }
        _ = try await authorizedRequest(path: "torrents/selectFiles/\(torrentId)", method: "POST", body: formBody(["files": selection]))
    }
    public func checkInstantAvailability(hashes: [String]) async throws -> [String: RDInstantAvailability] {
        // The current public API no longer advertises this endpoint. Unknown is not cached.
        [:]
    }
    public func deleteTorrent(id: String) async throws {
        _ = try await authorizedRequest(path: "torrents/delete/\(id)", method: "DELETE")
    }
    public func unrestrictLink(_ link: String) async throws -> RDUnrestrictResponse {
        let data = try await authorizedRequest(path: "unrestrict/link", method: "POST", body: formBody(["link": link]))
        return try decode(RDUnrestrictResponse.self, data: data, operation: .playbackLink)
    }

    public func resolveMagnetToStream(magnet: String, preferredFileIndex: Int? = nil) async throws -> PlayableStream {
        try await resolveMagnetToStream(magnet: magnet, preferredFileIndex: preferredFileIndex, preferredFileName: nil)
    }

    public func resolveMagnetToStream(magnet: String, preferredFileIndex: Int?, preferredFileName: String?) async throws -> PlayableStream {
        guard let hash = SourceStream.extractHash(from: magnet) else {
            throw RealDebridError.magnetAdditionFailed("Enter a valid v1 magnet link or SHA1 info-hash.")
        }
        let generation = locked { authGeneration }
        let existing: RDTorrentInfo?
        do {
            existing = try await reusableTorrent(hash: hash, fileIndex: preferredFileIndex, fileName: preferredFileName, generation: generation)
        } catch RealDebridError.responseDecodingFailed(let failure) where failure.operation == .cloudLookup {
            // Cloud reuse is an optimization. A malformed/unrelated cloud entry
            // must not prevent resolving the exact source the user selected.
            // Explicit HTTP/service/auth failures are not swallowed here.
            existing = nil
        }
        try requireAccount(generation)
        // A ready or already-preparing exact match does not need another addMagnet request.
        let torrentId: String
        if let existing { torrentId = existing.id }
        else { torrentId = try await addMagnet(magnet) }
        return try await prepareTorrent(id: torrentId, hash: hash, fileIndex: preferredFileIndex,
                                        fileName: preferredFileName, initialInfo: existing, generation: generation)
    }

    private func requireAccount(_ generation: Int) throws {
        try Task.checkCancellation()
        guard locked({ authGeneration == generation }) else { throw CancellationError() }
    }

    private func reusableTorrent(hash: String, fileIndex: Int?, fileName: String?, generation: Int) async throws -> RDTorrentInfo? {
        var pending: RDTorrentInfo?
        let pageSize = 100
        // Match by the actual v1 hash, never by movie/episode display titles.
        for page in 0..<25 {
            try requireAccount(generation)
            let cloudPage = try await getTorrentPage(offset: page * pageSize, limit: pageSize)
            let torrents = cloudPage.items
            for torrent in torrents where SourceStream.extractHash(from: torrent.hash) == hash {
                try requireAccount(generation)
                if ["error", "dead", "virus", "magnet_error"].contains(torrent.status) { continue }
                let info: RDTorrentInfo
                do { info = try await getTorrentInfo(id: torrent.id) }
                catch RealDebridError.requestFailed(let failure) where failure.statusCode == 404 || failure.code == 7 {
                    continue // Cloud entries can disappear between list and detail requests.
                } catch RealDebridError.responseDecodingFailed {
                    // An unreadable existing entry is not a reusable candidate.
                    // The normal exact-source path still validates its own detail response.
                    continue
                }
                try requireAccount(generation)
                guard SourceStream.extractHash(from: info.hash) == hash else { continue }
                if ["error", "dead", "virus", "magnet_error"].contains(info.status) { continue }
                if info.files.isEmpty { pending = pending ?? info; continue }
                let file = try info.requestedVideo(fileIndex: fileIndex, fileName: fileName)
                if info.isReadyToStream && file.isSelected {
                    _ = try info.link(forFileId: file.id)
                    return info
                }
                // Preserve files selected by Kodi/other clients. Only reuse an existing
                // preparation when it already includes this file, or nothing is selected yet.
                if !info.isReadyToStream && (file.isSelected || (info.isAwaitingFileSelection && !info.files.contains(where: \.isSelected))) {
                    pending = pending ?? info
                }
            }
            if cloudPage.rawItemCount < pageSize { break }
        }
        return pending
    }

    private func prepareTorrent(id torrentId: String, hash: String, fileIndex: Int?, fileName: String?,
                                initialInfo: RDTorrentInfo?, generation: Int) async throws -> PlayableStream {
        var initialInfo = initialInfo
        var firstNewInspection = initialInfo == nil
        for attempt in 0..<maxPreparationAttempts {
            try requireAccount(generation)
            let info: RDTorrentInfo
            if let first = initialInfo { info = first; initialInfo = nil }
            else if firstNewInspection {
                info = try await getNewTorrentInfo(id: torrentId)
                firstNewInspection = false
            }
            else { info = try await getTorrentInfo(id: torrentId) }
            try requireAccount(generation)
            guard SourceStream.extractHash(from: info.hash) == hash else {
                throw RealDebridError.debridLinkResolutionFailed("Real-Debrid returned a different torrent than the requested source. Playback was stopped to avoid choosing the wrong file.")
            }
            if ["error", "dead", "virus", "magnet_error"].contains(info.status) {
                throw RealDebridError.debridLinkResolutionFailed("Torrent preparation failed (\(info.status)).")
            }
            if !info.files.isEmpty {
                let file = try info.requestedVideo(fileIndex: fileIndex, fileName: fileName)
                if info.isAwaitingFileSelection {
                    let selected = info.files.filter(\.isSelected)
                    guard selected.isEmpty || file.isSelected else {
                        throw RealDebridError.debridLinkResolutionFailed("This cloud entry has other files selected. Choose the requested file in Debrid Cloud; existing selections were preserved.")
                    }
                    // Keep all existing selections instead of replacing a Kodi season pack
                    // with only the episode requested by this app.
                    let ids = selected.isEmpty ? [file.id] : selected.map(\.id)
                    try await selectFiles(torrentId: torrentId, fileIds: ids)
                } else if info.isReadyToStream {
                    let link = try info.link(forFileId: file.id)
                    let resolved = try await unrestrictLink(link)
                    try requireAccount(generation)
                    return try Self.playable(from: resolved)
                }
            }
            if attempt + 1 < maxPreparationAttempts { try await Task.sleep(nanoseconds: pollIntervalNanoseconds) }
        }
        throw RealDebridError.debridLinkResolutionFailed("The torrent is still preparing. Its cloud entry was preserved; check Debrid Cloud and retry when downloaded.")
    }

    static func playable(from response: RDUnrestrictResponse, source: SourceStream? = nil) throws -> PlayableStream {
        guard let url = URL(string: response.download), url.scheme?.lowercased() == "https", url.host != nil else {
            throw RealDebridError.debridLinkResolutionFailed("The service returned an invalid or insecure playback URL.")
        }
        return PlayableStream(streamURL: url, title: response.filename, filename: response.filename,
                              mimeType: response.mimeType, fileSize: response.filesize, originalSource: source)
    }
}
