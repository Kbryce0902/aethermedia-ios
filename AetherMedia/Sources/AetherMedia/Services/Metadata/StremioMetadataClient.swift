import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProviderServiceError: LocalizedError, Sendable {
    case unavailable(String)
    public var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

/// Public Stremio protocol transport. Account tokens are never sent to metadata/index services.
struct StremioTransport: Sendable {
    let session: URLSession
    func get<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderServiceError.unavailable("The media service is unavailable (HTTP \(code)). Try again later.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func escape(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public final class StremioMetadataClient: Sendable {
    public static let shared = StremioMetadataClient()
    private let transport: StremioTransport
    private let baseURL: URL
    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://v3-cinemeta.strem.io")!) {
        transport = StremioTransport(session: session)
        self.baseURL = baseURL
    }
    private func endpoint(_ path: String) -> URL {
        URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path)!
    }
    public func catalog(category: CatalogCategory) async throws -> [MediaItem] {
        let type: String
        switch category {
        case .popularShows: type = "series"
        case .trending, .popularMovies, .topRated: type = "movie"
        default: return []
        }
        let result = try await transport.get(CatalogResponse.self, url: endpoint("catalog/\(type)/top.json"))
        return result.metas.map { $0.item(fallbackType: type) }
    }
    public func search(query: String) async throws -> [MediaItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: [MediaItem].self) { group in
            for type in ["movie", "series"] {
                group.addTask { [self] in
                    let path = "catalog/\(type)/top/search=\(StremioTransport.escape(query)).json"
                    let result = try await transport.get(CatalogResponse.self, url: endpoint(path))
                    return result.metas.map { $0.item(fallbackType: type) }
                }
            }
            var items: [MediaItem] = []
            for try await batch in group { items += batch }
            return items
        }
    }
    public func details(for item: MediaItem) async throws -> MediaDetails {
        guard let imdb = item.imdbId ?? (item.id.hasPrefix("tt") ? item.id : nil) else {
            return MediaDetails(id: item.id, title: item.title, overview: item.overview, type: item.type)
        }
        let type = item.type == .tvShow || item.type == .anime ? "series" : "movie"
        let result = try await transport.get(MetaResponse.self, url: endpoint("meta/\(type)/\(StremioTransport.escape(imdb)).json"))
        let meta = result.meta
        let episodes = (meta.videos ?? []).compactMap { video -> Episode? in
            guard let season = video.season, let episode = video.episode, season >= 0, episode > 0 else { return nil }
            return Episode(id: video.id, seasonNumber: season, episodeNumber: episode, title: video.title ?? "Episode \(episode)",
                           overview: video.overview, stillURL: video.thumbnail.flatMap(URL.init(string:)), airDate: video.released)
        }
        let grouped = Dictionary(grouping: episodes, by: \.seasonNumber)
        let seasons = grouped.keys.sorted().map { season -> Season in
            let items = (grouped[season] ?? []).sorted { $0.episodeNumber < $1.episodeNumber }
            return Season(id: "\(imdb):\(season)", seasonNumber: season, name: season == 0 ? "Specials" : "Season \(season)", episodeCount: items.count, episodes: items)
        }
        return MediaDetails(id: item.id, title: meta.name, overview: meta.description ?? item.overview,
                            posterURL: meta.poster.flatMap(URL.init(string:)), backdropURL: meta.background.flatMap(URL.init(string:)),
                            releaseYear: meta.year, rating: meta.rating, genres: meta.genres ?? [], type: item.type, imdbId: imdb, seasons: seasons)
    }
}

private struct CatalogResponse: Decodable { let metas: [MetadataDTO] }
private struct MetaResponse: Decodable { let meta: MetadataDTO }
private struct MetadataDTO: Decodable {
    let id: String
    let name: String
    let type: String?
    let description: String?
    let poster: String?
    let background: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let videos: [VideoDTO]?
    var year: Int? { releaseInfo.flatMap { Int($0.prefix(4)) } }
    var rating: Double? { imdbRating.flatMap(Double.init) }
    func item(fallbackType: String) -> MediaItem {
        MediaItem(id: id, title: name, overview: description ?? "", posterURL: poster.flatMap(URL.init(string:)),
                  backdropURL: background.flatMap(URL.init(string:)), releaseYear: year, rating: rating,
                  type: (type ?? fallbackType) == "series" ? .tvShow : .movie, imdbId: id, providerId: "builtin.torrentio")
    }
}
private struct VideoDTO: Decodable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let released: String?
    let thumbnail: String?
    let overview: String?
}
