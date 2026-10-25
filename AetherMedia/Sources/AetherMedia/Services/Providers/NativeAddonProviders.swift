import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native, standalone source implementations. These do not claim to execute Kodi ZIP packages.
public struct NativeIndexEndpoints: Sendable {
    public let yts: URL
    public let eztv: URL
    public init(yts: URL = URL(string: "https://yts.mx")!, eztv: URL = URL(string: "https://eztvx.to")!) {
        self.yts = yts; self.eztv = eztv
    }
}

public final class NativeIndexClient: @unchecked Sendable {
    private let session: URLSession
    private let endpoints: NativeIndexEndpoints
    private let preferences: UserDefaults?
    public init(session: URLSession = .shared, endpoints: NativeIndexEndpoints = NativeIndexEndpoints(), preferences: UserDefaults? = .standard) {
        self.session = session; self.endpoints = endpoints; self.preferences = preferences
    }
    private func url(_ key: String, fallback: URL, path: String, query: [URLQueryItem]) throws -> URL {
        let saved = preferences?.string(forKey: "native.\(key).endpoint")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = saved.flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? fallback
        guard base.scheme?.lowercased() == "https", base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else {
            throw ProviderServiceError.unavailable("Use a valid HTTPS base URL in native source settings.")
        }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }
    private func get(_ url: URL) async throws -> Any {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProviderServiceError.unavailable("\(url.host ?? "Source index") is unavailable (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Try another provider or change its endpoint in Settings.")
        }
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw ProviderServiceError.unavailable("The source index returned an unreadable response. Try another provider.") }
    }
    private func imdb(_ item: MediaItem) -> String? {
        let value = item.imdbId ?? item.id
        return value.range(of: "^tt[0-9]+$", options: .regularExpression) != nil ? value : nil
    }
    private func number(_ object: Any?) -> Int64? {
        if let n = object as? NSNumber { return n.int64Value }
        return (object as? String).flatMap(Int64.init)
    }
    private func source(title: String, hash: String?, size: Int64?, seeds: Int64?, providerId: String, providerName: String) -> SourceStream? {
        guard let hash = SourceStream.extractHash(from: hash) else { return nil }
        return SourceStream(id: "\(providerId):\(hash)", title: title, providerName: providerName,
                            sizeBytes: size, seeds: seeds.map { Int(clamping: $0) }, isRealDebridCached: false,
                            magnetURL: "magnet:?xt=urn:btih:\(hash)", infoHash: hash, providerId: providerId)
    }
    public func serenSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        guard let imdb = imdb(item) else { return [] }
        if item.type == .movie {
            let endpoint = try url("yts", fallback: endpoints.yts, path: "api/v2/list_movies.json", query: [URLQueryItem(name: "query_term", value: imdb), URLQueryItem(name: "limit", value: "50")])
            guard let root = try await get(endpoint) as? [String: Any], root["status"] as? String == "ok",
                  let data = root["data"] as? [String: Any] else { throw ProviderServiceError.unavailable("Seren Native: the movie index did not return a valid result.") }
            var sources: [SourceStream] = []
            for movie in data["movies"] as? [[String: Any]] ?? [] {
                guard movie["imdb_code"] as? String == imdb else { continue }
                for torrent in movie["torrents"] as? [[String: Any]] ?? [] {
                    let title = [movie["title_long"] as? String ?? item.title, torrent["quality"] as? String ?? "", torrent["type"] as? String ?? "", torrent["video_codec"] as? String ?? ""].joined(separator: ".")
                    if let result = source(title: title, hash: torrent["hash"] as? String, size: number(torrent["size_bytes"]), seeds: number(torrent["seeds"]), providerId: "native.seren", providerName: "Seren Native · YTS") { sources.append(result) }
                }
            }
            return sources
        }
        guard let episode else { throw ProviderServiceError.unavailable("Choose an episode before searching Seren Native.") }
        var results: [SourceStream] = []
        // Walk enough pages to find older episodes, with a bounded, cancellable request budget.
        for page in 1...10 {
            let endpoint = try url("eztv", fallback: endpoints.eztv, path: "api/get-torrents", query: [URLQueryItem(name: "imdb_id", value: String(imdb.dropFirst(2))), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "page", value: String(page))])
            guard let response = try await get(endpoint) as? [String: Any] else { throw ProviderServiceError.unavailable("Seren Native: unreadable episode results.") }
            let torrents = response["torrents"] as? [[String: Any]] ?? []
            for torrent in torrents {
                guard number(torrent["season"]) == Int64(episode.seasonNumber), number(torrent["episode"]) == Int64(episode.episodeNumber) else { continue }
                if let reportedImdb = number(torrent["imdb_id"]), reportedImdb != Int64(imdb.dropFirst(2)) { continue }
                let title = torrent["filename"] as? String ?? torrent["title"] as? String ?? ""
                guard NativeReleaseMatcher.hasExactEpisode(title, episode: episode) else { continue }
                if let result = source(title: title, hash: torrent["hash"] as? String ?? torrent["magnet_url"] as? String, size: number(torrent["size_bytes"]), seeds: number(torrent["seeds"]), providerId: "native.seren", providerName: "Seren Native · EZTV") { results.append(result) }
            }
            let total = number(response["torrents_count"]) ?? Int64(torrents.count)
            if torrents.isEmpty || Int64(page * 100) >= total { break }
        }
        return results
    }

}

/// Conservative matching: no season packs or multi-episode releases without a known file index.
public enum NativeReleaseMatcher {
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    public static func hasExactEpisode(_ title: String, episode: Episode) -> Bool {
        let season = episode.seasonNumber, ep = episode.episodeNumber
        let pattern = "(?i)(?:^|[^a-z0-9])(?:s0*\(season)e0*\(ep)|0*\(season)x0*\(ep))(?![0-9eE]|[-_][eE]?[0-9]{1,3}(?![0-9pP]))"
        return title.range(of: pattern, options: .regularExpression) != nil
    }
    public static func matches(_ release: String, item: MediaItem, episode: Episode?, sourceImdbId: String? = nil) -> Bool {
        let requestedImdb = item.imdbId ?? (item.id.hasPrefix("tt") ? item.id : nil)
        if let sourceImdbId, sourceImdbId != requestedImdb { return false }
        let cleaned = normalized(release), name = normalized(item.title)
        guard !name.isEmpty, (cleaned == name || cleaned.hasPrefix(name + " ")),
              !cleaned.split(separator: " ").contains("sample"), !cleaned.split(separator: " ").contains("trailer") else { return false }
        if let episode {
            guard hasExactEpisode(release, episode: episode) else { return false }
            let suffix = cleaned.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            let first = suffix.split(separator: " ").first
            let editionYear = first.flatMap { token -> Int? in
                guard token.count == 4, let value = Int(token), (1900...2100).contains(value) else { return nil }
                return value
            }
            if let year = item.releaseYear, let editionYear, year != editionYear { return false }
            if let sourceImdbId, sourceImdbId == requestedImdb { return true }
            // Title + S01E01 alone cannot distinguish reboots. Without a
            // reported IMDb match, require the catalog's series edition year.
            guard let year = item.releaseYear else { return false }
            return name.split(separator: " ").last == Substring(String(year)) || editionYear == year
        }
        if release.range(of: "(?i)s[0-9]{1,2}e[0-9]{1,3}", options: .regularExpression) != nil { return false }
        if let year = item.releaseYear { return cleaned.split(separator: " ").contains(Substring(String(year))) }
        return true
    }
}

public struct SerenNativeProvider: MediaProviderProtocol {
    public let id = "native.seren", displayName = "Seren Sources (Native)", version = "0.3.0"
    public let capabilities: ProviderCapabilities = [.sourceDiscovery, .directPlayback]
    public let isEnabled = true, priority = 98
    public let supportedTypes: [MediaType] = [.movie, .tvShow, .anime]
    private let client: NativeIndexClient
    public init(client: NativeIndexClient = NativeIndexClient()) { self.client = client }
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] { [] }
    public func search(query: String) async throws -> [MediaItem] { [] }
    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] { try await client.serenSources(for: item, episode: episode) }
    public func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream { try await resolveNative(source: source, client: debridClient) }
}
private func resolveNative(source: SourceStream, client: RealDebridClientProtocol) async throws -> PlayableStream {
    guard let magnet = source.magnetURL else { throw RealDebridError.debridLinkResolutionFailed("No magnet was returned by this index.") }
    let stream = try await client.resolveMagnetToStream(magnet: magnet, preferredFileIndex: source.fileIndex, preferredFileName: source.originalFileName)
    return stream.withOriginalSource(source)
}
