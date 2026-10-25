import Foundation

/// HTTP services exposed by Red Light 2.9.1's native scraper modules.
public enum RedLightBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case comet, mediafusion, zilean, torz, torrentio, piratebay, torrentdownloads, animetosho, nyaa, aiostreams
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .comet: return "Comet"
        case .mediafusion: return "MediaFusion"
        case .zilean: return "Zilean"
        case .torz: return "StremThru Torz"
        case .torrentio: return "Torrentio"
        case .piratebay: return "PirateBay / APIBay"
        case .torrentdownloads: return "Torrent Downloads"
        case .animetosho: return "AnimeTosho"
        case .nyaa: return "Nyaa"
        case .aiostreams: return "AIOStreams"
        }
    }
    public var defaultEndpoint: String {
        switch self {
        case .comet: return "https://comet.feels.legal"
        case .mediafusion: return "https://mediafusionfortheweebs.midnightignite.me"
        case .zilean: return "https://zilean.stremio.ru"
        case .torz: return "https://stremthru.stremio.ru"
        case .torrentio: return "https://torrentio.strem.fun"
        case .piratebay: return "https://apibay.org"
        case .torrentdownloads: return "https://www.torrentdownloads.pro"
        case .animetosho: return "https://feed.animetosho.org"
        case .nyaa: return "https://nyaa.si"
        case .aiostreams: return "https://aiostreams.stremio.ru"
        }
    }
    public var animeOnly: Bool { self == .nyaa || self == .animetosho }
}

public struct RedLightConfiguration: Codable, Sendable {
    public var enabled: Set<RedLightBackend> = Set(RedLightBackend.allCases.filter { $0 != .aiostreams })
    public var endpoints: [String: String] = [:]
    public var includeSeasonPacks = true
    public var aioUsername = ""
    public var aioPassword = ""
    public var timeout: Double = 20
    public init() {}
    public func endpoint(for backend: RedLightBackend) -> String {
        let saved = endpoints[backend.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? backend.defaultEndpoint : saved
    }
    public func validatedEndpoint(for backend: RedLightBackend) throws -> URL {
        var value = endpoint(for: backend).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Stremio configuration pages supply a manifest URL. Keep its private config path.
        if value.hasSuffix("/manifest.json") { value = String(value.dropLast(14)) }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ProviderServiceError.unavailable("\(backend.name): enter a valid HTTPS instance or manifest URL in Red Light settings.")
        }
        return url
    }
    public func validate() throws {
        for backend in enabled { _ = try validatedEndpoint(for: backend) }
        guard timeout.isFinite, (5...60).contains(timeout) else {
            throw ProviderServiceError.unavailable("Choose a source timeout between 5 and 60 seconds.")
        }
        if enabled.contains(.aiostreams), (aioUsername.isEmpty || aioPassword.isEmpty) {
            throw ProviderServiceError.unavailable("AIOStreams needs the Search API username and password from your selected instance. These are separate from Real-Debrid authorization.")
        }
    }
}

/// Private instance paths and AIO credentials belong in Keychain, never source or UserDefaults.
public final class RedLightSettingsStore: @unchecked Sendable {
    public static let shared = RedLightSettingsStore()
    private let keychain: KeychainService
    private let preferences: UserDefaults?
    public init(keychain: KeychainService = .shared, preferences: UserDefaults? = .standard) {
        self.keychain = keychain; self.preferences = preferences
    }
    public func load() -> RedLightConfiguration {
        if let text = keychain.get(key: .redLightConfiguration), let data = text.data(using: .utf8),
           let saved = try? JSONDecoder().decode(RedLightConfiguration.self, from: data) { return saved }
        var defaults = RedLightConfiguration()
        if let legacy = preferences?.string(forKey: "native.redlight.endpoint"), !legacy.isEmpty {
            defaults.endpoints[RedLightBackend.piratebay.rawValue] = legacy
        }
        return defaults
    }
    public func save(_ configuration: RedLightConfiguration) throws {
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        guard let value = String(data: data, encoding: .utf8), keychain.save(key: .redLightConfiguration, value: value) else {
            throw ProviderServiceError.unavailable("Red Light settings could not be saved securely. Unlock your iPhone and try again.")
        }
        preferences?.removeObject(forKey: "native.redlight.endpoint")
    }
}
