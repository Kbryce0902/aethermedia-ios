import Foundation

// MARK: - OAuth & Device Code Responses

public struct RDDeviceCodeResponse: Codable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let interval: Int
    public let expiresIn: Int
    public let verificationUrl: String
    
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case interval
        case expiresIn = "expires_in"
        case verificationUrl = "verification_url"
    }
}

public struct RDCredentialsResponse: Codable, Sendable {
    public let clientId: String
    public let clientSecret: String
    
    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }
}

public struct RDTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    public let tokenType: String
    public let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
    }
}

// MARK: - User Account

public struct RDUser: Codable, Sendable, Equatable {
    public let id: Int
    public let username: String
    public let email: String?
    public let points: Int
    public let type: String  // "premium" or "free"
    public let expiration: String?
    
    public var isPremium: Bool {
        type.lowercased() == "premium"
    }
}

// MARK: - Torrents & Cloud Storage

public struct RDTorrent: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let hash: String
    public let bytes: Int64
    public let host: String
    public let split: Int?
    public let progress: Double
    public let status: String
    public let added: String
    public let links: [String]
    public let ended: String?
    public let speed: Int?
    public let seeders: Int?
    
    public var isReadyToStream: Bool {
        status == "downloaded" && !links.isEmpty
    }
    
    public var isAwaitingFileSelection: Bool {
        status == "waiting_files_selection"
    }
    
    public var formattedSize: String {
        guard bytes > 0 else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

public struct RDTorrentInfo: Codable, Sendable {
    public let id: String
    public let filename: String
    public let originalFilename: String?
    public let hash: String
    public let bytes: Int64
    public let host: String
    public let progress: Double
    public let status: String
    public let added: String
    public let files: [RDTorrentFile]
    public let links: [String]
    public let ended: String?
    public let speed: Int?
    public let seeders: Int?

    public var isAwaitingFileSelection: Bool { status == "waiting_files_selection" }
    public var isReadyToStream: Bool { status == "downloaded" && !links.isEmpty }

    /// Filename hints identify the actual requested video even if a provider's
    /// file index differs from the order returned by the cloud API.
    public func requestedVideo(fileIndex: Int?, fileName: String?) throws -> RDTorrentFile {
        func normalize(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        let videos = files.filter(\.isVideo)
        if let fileName, !fileName.isEmpty {
            let hint = normalize(fileName)
            let exact = videos.filter { normalize($0.path) == hint }
            let matches = exact.isEmpty ? videos.filter { normalize($0.path).split(separator: "/").last == hint.split(separator: "/").last } : exact
            guard matches.count == 1, let file = matches.first else {
                throw RealDebridError.debridLinkResolutionFailed("The source filename does not uniquely match a video in this torrent. Choose the exact file in Debrid Cloud.")
            }
            return file
        }
        if let index = fileIndex {
            guard files.indices.contains(index), files[index].isVideo else {
                throw RealDebridError.debridLinkResolutionFailed("The source file index does not match a video in this torrent.")
            }
            return files[index]
        }
        guard videos.count == 1, let file = videos.first else {
            throw RealDebridError.debridLinkResolutionFailed("This torrent has no single unambiguous video. Choose the exact file in Debrid Cloud.")
        }
        return file
    }

    /// RD links correspond to selected files in file order, not to file IDs.
    /// Refuse ambiguous (e.g. split archive) responses rather than play a different file.
    public func link(forFileId fileId: Int) throws -> String {
        let selectedFiles = files.filter(\.isSelected)
        guard isReadyToStream, selectedFiles.count == links.count,
              let index = selectedFiles.firstIndex(where: { $0.id == fileId }) else {
            throw RealDebridError.debridLinkResolutionFailed("This file has no unambiguous ready download link. Select it in your Real-Debrid cloud and retry.")
        }
        return links[index]
    }
    
    enum CodingKeys: String, CodingKey {
        case id, filename, hash, bytes, host, progress, status, added, files, links, ended, speed, seeders
        case originalFilename = "original_filename"
    }
}

public struct RDTorrentFile: Identifiable, Codable, Sendable {
    public let id: Int
    public let path: String
    public let bytes: Int64
    public let selected: Int
    
    public var isSelected: Bool { selected == 1 }
    
    public var isVideo: Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mkv") || lower.hasSuffix(".m4v") ||
               lower.hasSuffix(".avi") || lower.hasSuffix(".mov") || lower.hasSuffix(".webm") ||
               lower.hasSuffix(".ts") || lower.hasSuffix(".m2ts") || lower.hasSuffix(".mpg") || lower.hasSuffix(".mpeg")
    }
}

public struct RDAddMagnetResponse: Codable, Sendable {
    public let id: String
    public let uri: String?
}

// MARK: - Unrestrict Link

public struct RDUnrestrictResponse: Codable, Sendable {
    public let id: String
    public let filename: String
    public let mimeType: String?
    public let filesize: Int64
    public let link: String
    public let host: String
    public let chunks: Int?
    public let download: String
    public let streamable: Int?
    
    public var isStreamable: Bool {
        streamable == 1
    }
}

// MARK: - Instant Availability Container

public struct RDInstantAvailability: Sendable {
    public let hash: String
    public let isCached: Bool
    
    public init(hash: String, isCached: Bool) {
        self.hash = hash
        self.isCached = isCached
    }
}


// Decode wire representations without weakening torrent/file identity or URL checks.
// Presentation metadata can be absent/null; unknown telemetry stays unknown.
private extension KeyedDecodingContainer {
    func rdString(_ key: Key) -> String? { try? decodeIfPresent(String.self, forKey: key) }
    func rdRequiredString(_ key: Key) throws -> String {
        let value = try decode(String.self, forKey: key)
        guard !value.isEmpty else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Required identifier is empty") }
        return value
    }
    func rdInteger<T: FixedWidthInteger & Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        if let value = try? decode(type, forKey: key) { return value }
        if let raw = try? decode(String.self, forKey: key),
           let value = T(raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        return try decode(type, forKey: key) // Preserve missing/null/type diagnostic.
    }
    func rdOptionalInteger<T: FixedWidthInteger & Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? rdInteger(type, key)
    }
    func rdProgress(_ key: Key) -> Double {
        let value = (try? decode(Double.self, forKey: key)) ?? rdString(key).flatMap(Double.init) ?? 0
        return value.isFinite && (0...100).contains(value) ? value : 0
    }
    func rdFlag(_ key: Key) throws -> Int {
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        let value = try rdInteger(Int.self, key)
        guard value == 0 || value == 1 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Selected flag must be 0 or 1")
        }
        return value
    }
}

extension RDTorrent {
    private enum CodingKeys: String, CodingKey { case id, filename, hash, bytes, host, split, progress, status, added, links, ended, speed, seeders }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.rdRequiredString(.id)
        hash = try c.rdRequiredString(.hash)
        status = try c.rdRequiredString(.status)
        filename = c.rdString(.filename) ?? "Unnamed torrent"
        bytes = max(0, c.rdOptionalInteger(Int64.self, .bytes) ?? 0)
        host = c.rdString(.host) ?? ""
        split = c.rdOptionalInteger(Int.self, .split)
        progress = c.rdProgress(.progress)
        added = c.rdString(.added) ?? ""
        links = try c.decodeIfPresent([String].self, forKey: .links) ?? []
        ended = c.rdString(.ended)
        speed = c.rdOptionalInteger(Int.self, .speed)
        seeders = c.rdOptionalInteger(Int.self, .seeders)
    }
}

extension RDTorrentInfo {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.rdRequiredString(.id)
        hash = try c.rdRequiredString(.hash)
        status = try c.rdRequiredString(.status)
        filename = c.rdString(.filename) ?? "Unnamed torrent"
        originalFilename = c.rdString(.originalFilename)
        bytes = max(0, c.rdOptionalInteger(Int64.self, .bytes) ?? 0)
        host = c.rdString(.host) ?? ""
        progress = c.rdProgress(.progress)
        added = c.rdString(.added) ?? ""
        files = try c.decodeIfPresent([RDTorrentFile].self, forKey: .files) ?? []
        links = try c.decodeIfPresent([String].self, forKey: .links) ?? []
        ended = c.rdString(.ended)
        speed = c.rdOptionalInteger(Int.self, .speed)
        seeders = c.rdOptionalInteger(Int.self, .seeders)
    }
}

extension RDTorrentFile {
    private enum CodingKeys: String, CodingKey { case id, path, bytes, selected }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.rdInteger(Int.self, .id)
        guard id > 0 else { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "File identifier must be positive") }
        path = try c.rdRequiredString(.path)
        bytes = max(0, c.rdOptionalInteger(Int64.self, .bytes) ?? 0)
        selected = try c.rdFlag(.selected)
    }
}

extension RDUnrestrictResponse {
    private enum CodingKeys: String, CodingKey { case id, filename, mimeType, filesize, link, host, chunks, download, streamable }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.rdRequiredString(.id)
        download = try c.rdRequiredString(.download)
        filename = c.rdString(.filename) ?? URL(string: download)?.lastPathComponent ?? "Video"
        mimeType = c.rdString(.mimeType)
        filesize = max(0, c.rdOptionalInteger(Int64.self, .filesize) ?? 0)
        link = c.rdString(.link) ?? ""
        host = c.rdString(.host) ?? ""
        chunks = c.rdOptionalInteger(Int.self, .chunks)
        streamable = try? c.rdFlag(.streamable)
    }
}
