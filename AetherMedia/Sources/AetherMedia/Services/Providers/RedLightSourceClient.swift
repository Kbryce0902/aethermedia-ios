import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Independent Swift implementation of the HTTP protocols used by Red Light's native sources.
/// No Kodi process, Python runtime, add-on download or third-party credential forwarding.
public final class RedLightSourceClient: @unchecked Sendable {
    private let session: URLSession
    private let settings: @Sendable () -> RedLightConfiguration
    public init(session: URLSession? = nil, configuration: (@Sendable () -> RedLightConfiguration)? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: RedLightRedirectGuard(), delegateQueue: nil)
        self.settings = configuration ?? { RedLightSettingsStore.shared.load() }
    }

    public func discover(for item: MediaItem, episode: Episode?) async throws -> SourceDiscoveryResult {
        if item.type != .movie && episode == nil {
            throw ProviderServiceError.unavailable("Choose an episode before searching Red Light.")
        }
        let configuration = settings()
        let deadline = Date().addingTimeInterval(min(60, max(5, configuration.timeout)))
        let backends = RedLightBackend.allCases.filter {
            configuration.enabled.contains($0) && (!$0.animeOnly || item.type == .anime)
        }
        let batches = try await withThrowingTaskGroup(of: SourceDiscoveryResult.self) { group in
            for backend in backends {
                group.addTask { [self] in
                    do {
                        let base = try configuration.validatedEndpoint(for: backend)
                        let records = try await search(backend, base: base, item: item, episode: episode,
                                                       configuration: configuration, deadline: deadline)
                        return Self.batch(records, backend: backend, item: item, episode: episode, configuration: configuration)
                    } catch {
                        try Task.checkCancellation()
                        if let partial = error as? PartialSearch {
                            return Self.batch(partial.records, backend: backend, item: item, episode: episode,
                                              configuration: configuration, issue: partial.message)
                        }
                        let message: String
                        if let error = error as? ProviderServiceError { message = error.localizedDescription }
                        else if (error as? URLError)?.code == .timedOut { message = "Source search timed out. Try a different instance in Red Light settings." }
                        else { message = "Source search could not connect or read its response. Try a different instance in Red Light settings." }
                        // No URL, response body, AIO username or private config path enters diagnostics.
                        return SourceDiscoveryResult(sources: [], warnings: ["Red Light · \(backend.name): \(message)"],
                            reports: [SourceBackendReport(id: backend.id, name: backend.name, status: "failed", message: message)])
                    }
                }
            }
            var results: [SourceDiscoveryResult] = []
            for try await result in group { results.append(result) }
            return results
        }
        try Task.checkCancellation()
        var warnings = batches.flatMap(\.warnings)
        if backends.isEmpty { warnings.append("Red Light has no enabled services for this title. Open Red Light settings to enable them.") }
        return SourceDiscoveryResult(sources: batches.flatMap(\.sources), warnings: warnings.sorted(),
                                     reports: batches.flatMap(\.reports).sorted { $0.id < $1.id })
    }

    private struct Record: Sendable {
        var name: String
        var hash: String?
        var url: URL?
        var size: Int64?
        var seeds: Int?
        var index: Int?
        var filename: String?
        var imdb: String?
        var identityBound = false
    }
    private struct PartialSearch: Error {
        let records: [Record]
        let message: String
    }
    private static func batch(_ records: [Record], backend: RedLightBackend, item: MediaItem, episode: Episode?,
                              configuration: RedLightConfiguration, issue: String? = nil) -> SourceDiscoveryResult {
        var seen = Set<String>()
        let sources = records.compactMap { source($0, backend: backend, item: item, episode: episode, configuration: configuration) }
            .filter { seen.insert($0.id).inserted }
        return SourceDiscoveryResult(sources: sources, warnings: issue.map { ["Red Light · \(backend.name): \($0)"] } ?? [],
            reports: [SourceBackendReport(id: backend.id, name: backend.name, status: issue == nil ? "responded" : "partial",
                                          received: records.count, accepted: sources.count, message: issue)])
    }
    private static func integer(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        return (value as? String).flatMap(Int64.init)
    }
    private static func hash(_ value: Any?) -> String? {
        guard let hash = SourceStream.extractHash(from: value as? String), hash != String(repeating: "0", count: 40) else { return nil }
        return hash
    }
    private static func https(_ value: Any?) -> URL? {
        guard let value = value as? String, let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil, !value.contains("|") else { return nil }
        let path = url.path.lowercased()
        guard !path.contains("/static/downloading"), !path.contains("/static/uncached"),
              !path.hasSuffix("/configure"), !path.hasSuffix("manifest.json") else { return nil }
        return url
    }
    private static func imdb(_ item: MediaItem) -> String? {
        let id = item.imdbId ?? item.id
        return id.range(of: "^tt[0-9]+$", options: .regularExpression) == nil ? nil : id
    }
    private static func mediaID(_ item: MediaItem) -> String? {
        imdb(item) ?? item.tmdbId.flatMap { $0 > 0 ? "tmdb:\($0)" : nil }
    }
    private static func size(_ value: String) -> Int64? {
        guard let range = value.range(of: "(?i)[0-9]+(?:[.,][0-9]+)*\\s*(?:GiB|GB|MiB|MB)", options: .regularExpression) else { return nil }
        let text = String(value[range]).replacingOccurrences(of: ",", with: "")
        let number = text.prefix { $0.isNumber || $0 == "." }
        guard let n = Double(number), n.isFinite, n > 0 else { return nil }
        let bytes = n * (text.uppercased().contains("G") ? 1_073_741_824 : 1_048_576)
        return bytes < Double(Int64.max) ? Int64(bytes) : nil
    }
    private func endpoint(_ base: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        var c = URLComponents(url: path.isEmpty ? base : base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { throw ProviderServiceError.unavailable("Invalid source endpoint. Check Red Light settings.") }
        return url
    }
    private func data(_ url: URL, deadline: Date, basic: String? = nil) async throws -> Data {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.timeoutInterval = min(20, remaining)
        request.setValue("application/json, application/rss+xml, application/xml", forHTTPHeaderField: "Accept")
        request.setValue("AetherMedia/0.3.6", forHTTPHeaderField: "User-Agent")
        if let basic { request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderServiceError.unavailable("HTTP \(status). Check the instance URL and service settings.")
        }
        guard data.count <= 8_000_000 else { throw ProviderServiceError.unavailable("Source response exceeded the search size limit.") }
        return data
    }
    private func json(_ url: URL, deadline: Date, basic: String? = nil) async throws -> Any {
        let body = try await data(url, deadline: deadline, basic: basic)
        guard let value = try? JSONSerialization.jsonObject(with: body) else {
            throw ProviderServiceError.unavailable("The service returned an unreadable response. Check its instance URL.")
        }
        return value
    }

    private func search(_ backend: RedLightBackend, base: URL, item: MediaItem, episode: Episode?,
                        configuration: RedLightConfiguration, deadline: Date) async throws -> [Record] {
        switch backend {
        case .comet, .mediafusion, .torrentio:
            guard let id = Self.mediaID(item) else { return [] }
            let videoID = episode.map { "\(id):\($0.seasonNumber):\($0.episodeNumber)" } ?? id
            let url = try endpoint(base, path: "stream/\(episode == nil ? "movie" : "series")/\(videoID).json")
            guard let root = try await json(url, deadline: deadline) as? [String: Any], let raw = root["streams"] as? [[String: Any]] else {
                throw ProviderServiceError.unavailable("The instance did not return a stream list.")
            }
            return raw.prefix(1500).compactMap { Self.streamRecord($0) }
        case .zilean:
            guard let imdb = Self.imdb(item) else { return [] }
            var query = [URLQueryItem(name: "ImdbId", value: imdb)]
            if let episode { query += [URLQueryItem(name: "Season", value: String(episode.seasonNumber)), URLQueryItem(name: "Episode", value: String(episode.episodeNumber))] }
            let payload = try await json(endpoint(base, path: "dmm/filtered", query: query), deadline: deadline)
            let root = payload as? [String: Any]
            guard let raw = (payload as? [[String: Any]]) ?? (root?["files"] as? [[String: Any]]) ?? (root?["results"] as? [[String: Any]]) else {
                throw ProviderServiceError.unavailable("The instance did not return a Zilean result list.")
            }
            return raw.prefix(1500).map { Self.indexRecord($0, name: $0["raw_title"] as? String ?? $0["filename"] as? String ?? $0["name"] as? String ?? "", bound: true) }
        case .torz:
            guard let id = Self.mediaID(item) else { return [] }
            let sid = episode.map { "\(id):\($0.seasonNumber):\($0.episodeNumber)" } ?? id
            let payload = try await json(endpoint(base, path: "v0/torrents", query: [URLQueryItem(name: "sid", value: sid)]), deadline: deadline)
            guard let root = payload as? [String: Any], let body = root["data"] as? [String: Any], let raw = body["items"] as? [[String: Any]] else {
                throw ProviderServiceError.unavailable("The instance did not return a Torz result list.")
            }
            return raw.prefix(1500).map { Self.indexRecord($0, name: $0["name"] as? String ?? "", bound: true) }
        case .aiostreams:
            guard !configuration.aioUsername.isEmpty, !configuration.aioPassword.isEmpty else {
                throw ProviderServiceError.unavailable("Set your instance's AIOStreams Search API username and password in Red Light settings.")
            }
            guard let id = Self.mediaID(item) else { return [] }
            let videoID = episode.map { "\(id):\($0.seasonNumber):\($0.episodeNumber)" } ?? id
            let basic = Data("\(configuration.aioUsername):\(configuration.aioPassword)".utf8).base64EncodedString()
            let payload = try await json(endpoint(base, path: "api/v1/search", query: [URLQueryItem(name: "type", value: episode == nil ? "movie" : "series"), URLQueryItem(name: "id", value: videoID)]), deadline: deadline, basic: basic)
            guard let root = payload as? [String: Any], root["success"] as? Bool != false,
                  let body = root["data"] as? [String: Any], let raw = body["results"] as? [[String: Any]] else {
                throw ProviderServiceError.unavailable("AIOStreams Search API did not return results. Check your instance and Search API credentials.")
            }
            if raw.isEmpty, let errors = body["errors"] as? [Any], !errors.isEmpty {
                throw ProviderServiceError.unavailable("AIOStreams reported provider errors. Check your configured providers on that instance.")
            }
            let records = raw.prefix(1500).compactMap { Self.aioRecord($0) }
            let headerDependent = raw.contains {
                let merged = Self.aioFields($0)
                return !(merged["requestHeaders"] as? [String: String] ?? merged["request_headers"] as? [String: String] ?? [:]).isEmpty
            }
            if headerDependent {
                throw PartialSearch(records: records, message: "Header-dependent streams were excluded. Other supported AIOStreams results remain available.")
            }
            if let errors = body["errors"] as? [Any], !errors.isEmpty {
                throw PartialSearch(records: records, message: "Some AIOStreams providers reported errors. Available results were retained.")
            }
            return records
        case .piratebay, .torrentdownloads, .animetosho, .nyaa:
            // Name indexes do not implement IMDb + episode search. Search release names instead.
            let title = item.title.replacingOccurrences(of: "&", with: "and")
            var queries = [episode.map { "\(title) \($0.code)" } ?? "\(title)\(item.releaseYear.map { " \($0)" } ?? "")"]
            if let episode, configuration.includeSeasonPacks { queries.append("\(title) S\(String(format: "%02d", episode.seasonNumber))") }
            var records: [Record] = []
            do { for query in queries {
                try Task.checkCancellation()
                if Date() >= deadline { if !records.isEmpty { break }; throw URLError(.timedOut) }
                let found: [Record]
                switch backend {
                case .piratebay:
                    let payload = try await json(endpoint(base, path: "q.php", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "cat", value: "0")]), deadline: deadline)
                    guard let raw = payload as? [[String: Any]] else { throw ProviderServiceError.unavailable("APIBay did not return a source list.") }
                    found = raw.prefix(1500).filter { (Self.integer($0["id"]) ?? 0) > 0 }.map { Self.indexRecord($0, name: $0["name"] as? String ?? "", bound: false) }
                case .animetosho:
                    let payload = try await json(endpoint(base, path: "json", query: [URLQueryItem(name: "q", value: query)]), deadline: deadline)
                    guard let raw = payload as? [[String: Any]] else { throw ProviderServiceError.unavailable("AnimeTosho did not return a source list.") }
                    found = raw.prefix(1500).map { Self.indexRecord($0, name: $0["torrent_name"] as? String ?? $0["title"] as? String ?? "", bound: false) }
                default:
                    let queryItems = backend == .nyaa
                        ? [URLQueryItem(name: "page", value: "rss"), URLQueryItem(name: "c", value: "0_0"), URLQueryItem(name: "f", value: "0"), URLQueryItem(name: "q", value: query)]
                        : [URLQueryItem(name: "new", value: "1"), URLQueryItem(name: "type", value: "search"), URLQueryItem(name: "cid", value: episode == nil ? "4" : "8"), URLQueryItem(name: "search", value: query)]
                    let body = try await data(endpoint(base, path: backend == .nyaa ? "" : "rss.xml", query: queryItems), deadline: deadline)
                    let reader = RedLightRSSReader()
                    let parser = XMLParser(data: body); parser.shouldResolveExternalEntities = false; parser.delegate = reader
                    guard parser.parse(), reader.sawRSS else { throw ProviderServiceError.unavailable("The index did not return a valid RSS feed.") }
                    found = reader.items.prefix(1500).map { raw in
                        Record(name: raw["title"] ?? "", hash: Self.hash(raw["info_hash"] ?? raw["infohash"]),
                               size: Int64(raw["size"] ?? "") ?? Self.size(raw["size"] ?? ""), seeds: Int(raw["seeders"] ?? ""))
                    }
                }
                records += found
            } } catch {
                try Task.checkCancellation()
                if !records.isEmpty { throw PartialSearch(records: records, message: "Some index queries could not finish. Available results were retained.") }
                throw error
            }
            return records
        }
    }

    private static func indexRecord(_ raw: [String: Any], name: String, bound: Bool) -> Record {
        let rawID = (raw["imdb"] as? String) ?? (raw["imdb_id"] as? String) ?? (raw["imdb_id"] as? NSNumber)?.stringValue
        let id = rawID.map { $0.hasPrefix("tt") ? $0 : "tt" + $0 }
        return Record(name: name, hash: hash(raw["info_hash"] ?? raw["infoHash"] ?? raw["hash"]),
                      size: integer(raw["size"] ?? raw["filesize"] ?? raw["total_size"]), seeds: integer(raw["seeders"]).map { Int(clamping: $0) }, imdb: id, identityBound: bound)
    }
    private static func streamRecord(_ raw: [String: Any]) -> Record? {
        let hints = raw["behaviorHints"] as? [String: Any] ?? [:]
        let text = raw["description"] as? String ?? raw["title"] as? String ?? ""
        let line = text.replacingOccurrences(of: "┈➤", with: "\n").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("💾") && !$0.contains("👤") && !$0.contains("⚙") && !$0.hasPrefix("📹") && !$0.hasPrefix("⭐") } ?? ""
        let release = line.replacingOccurrences(of: "^📄\\s*", with: "", options: .regularExpression)
        let filename = hints["filename"] as? String
        let name = filename ?? (release.isEmpty ? raw["name"] as? String ?? "" : release)
        let hash = Self.hash(raw["infoHash"]) ?? Self.hash(raw["url"])
        // Native Red Light torrent sites return torrents. Authenticated wrappers belong to AIOStreams.
        guard hash != nil else { return nil }
        return Record(name: name, hash: hash, size: integer(hints["videoSize"]) ?? size(text),
                      seeds: seedCount(text), index: integer(raw["fileIdx"] ?? hints["fileIdx"]).flatMap { $0 >= 0 && $0 < Int64(Int.max) ? Int($0) : nil },
                      filename: filename, identityBound: true)
    }
    private static func seedCount(_ text: String) -> Int? {
        guard let range = text.range(of: "(?i)(?:👤|seeders?)\\s*:?\\s*[0-9]+", options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }
    private static func aioFields(_ raw: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]
        for key in ["parsedFile", "streamData", "info"] {
            (raw[key] as? [String: Any] ?? [:]).forEach { merged[$0.key] = $0.value }
        }
        raw.forEach { merged[$0.key] = $0.value }
        return merged
    }
    private static func aioRecord(_ raw: [String: Any]) -> Record? {
        let merged = aioFields(raw)
        guard !(merged["type"] as? String ?? "").lowercased().contains("p2p") else { return nil }
        let headers = merged["requestHeaders"] as? [String: String] ?? merged["request_headers"] as? [String: String] ?? [:]
        // Do not silently hand a header-dependent URL to a player that cannot honor it.
        guard headers.isEmpty else { return nil }
        let hash = Self.hash(merged["infoHash"]) ?? Self.hash(merged["url"])
        let direct = https(merged["url"])
        guard hash != nil || direct != nil else { return nil }
        return Record(name: merged["filename"] as? String ?? merged["name"] as? String ?? "", hash: hash, url: direct,
                      size: integer(merged["size"]), index: integer(merged["fileIdx"]).flatMap { $0 >= 0 && $0 < Int64(Int.max) ? Int($0) : nil },
                      filename: merged["filename"] as? String, identityBound: true)
    }
    private static func source(_ record: Record, backend: RedLightBackend, item: MediaItem, episode: Episode?, configuration: RedLightConfiguration) -> SourceStream? {
        guard record.hash != nil || record.url != nil, !record.name.isEmpty,
              RedLightReleaseMatcher.matches(record.name, item: item, episode: episode,
                sourceImdb: record.imdb, identityBound: record.identityBound,
                allowPacks: configuration.includeSeasonPacks) else { return nil }
        let isPack = episode.map { !NativeReleaseMatcher.hasExactEpisode(record.name, episode: $0) } ?? false
        guard !isPack || record.hash != nil else { return nil }
        return SourceStream(id: "native.redlight:\(backend.id):\(record.hash ?? record.url!.absoluteString):\(record.index ?? -1)",
                            title: record.name, providerName: "Red Light · \(backend.name)", sizeBytes: record.size, seeds: record.seeds,
                            magnetURL: record.hash.map { "magnet:?xt=urn:btih:\($0)" }, infoHash: record.hash,
                            fileIndex: isPack ? nil : record.index, originalFileName: isPack ? nil : record.filename,
                            providerId: "native.redlight", directURL: record.url,
                            targetSeason: episode?.seasonNumber, targetEpisode: episode?.episodeNumber)
    }
}

/// Search endpoint identity permits yearless TV releases; explicit contradictory years/IMDb never do.
public enum RedLightReleaseMatcher {
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    public static func matches(_ release: String, item: MediaItem, episode: Episode?, sourceImdb: String? = nil,
                               identityBound: Bool, allowPacks: Bool) -> Bool {
        if let sourceImdb, sourceImdb != (item.imdbId ?? item.id) { return false }
        let name = normalized(item.title), text = normalized(release)
        // Anime release groups are not part of the series title.
        let withoutGroup = normalized(release.replacingOccurrences(of: "^\\[[^\\]]+\\]\\s*", with: "", options: .regularExpression))
        let candidate = text.hasPrefix(name + " ") || text == name ? text : withoutGroup
        guard !name.isEmpty, candidate == name || candidate.hasPrefix(name + " ") else { return false }
        let suffix = candidate.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        let tokens = suffix.split(separator: " ")
        guard !tokens.contains("sample"), !tokens.contains("trailer"), !tokens.contains("extras") else { return false }
        let edition = tokens.first.flatMap { token -> Int? in
            guard token.count == 4, let year = Int(token), (1900...2100).contains(year) else { return nil }; return year
        }
        if let edition, let year = item.releaseYear, edition != year { return false }
        let bound = identityBound || (sourceImdb != nil && sourceImdb == (item.imdbId ?? item.id))
        if episode == nil {
            guard release.range(of: "(?i)(?:s[0-9]{1,2}e[0-9]|[0-9]{1,2}x[0-9])", options: .regularExpression) == nil else { return false }
            return bound || item.releaseYear == nil || edition == item.releaseYear
        }
        guard let episode else { return false }
        if !bound, let year = item.releaseYear, edition != year,
           name.split(separator: " ").last != Substring(String(year)) { return false }
        if NativeReleaseMatcher.hasExactEpisode(release, episode: episode) { return true }
        guard allowPacks else { return false }
        let season = episode.seasonNumber
        // Never interpret a wrong single episode as a season pack.
        if release.range(of: "(?i)s[0-9]{1,2}e[0-9]{1,3}|[0-9]{1,2}x[0-9]{1,3}", options: .regularExpression) != nil { return false }
        let seasonPattern = "(?i)(?:^|[^a-z0-9])(?:s0*\(season)|season[ ._-]*0*\(season))(?![0-9a-z])"
        return release.range(of: seasonPattern, options: .regularExpression) != nil
    }
}

private final class RedLightRSSReader: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    var sawRSS = false
    private var row: [String: String]?
    private var field = ""
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = elementName.lowercased().split(separator: ":").last.map(String.init) ?? ""
        if name == "rss" || name == "rdf" { sawRSS = true }
        if name == "item" { row = [:] }
        field = name; text = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased().split(separator: ":").last.map(String.init) ?? ""
        if name == "item", let row { if items.count < 1500 { items.append(row) }; self.row = nil }
        else if row != nil, field == name { row?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        field = ""; text = ""
    }
}

private final class RedLightRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https" else { completionHandler(nil); return }
        // Search credentials and private instance paths must not be forwarded to another origin.
        guard task.originalRequest?.url?.host == request.url?.host,
              task.originalRequest?.url?.port == request.url?.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}
