import Foundation

/// Video resolution enum
public enum VideoResolution: String, Codable, Sendable, Comparable {
    case res4K = "4K"
    case res1080p = "1080p"
    case res720p = "720p"
    case res480p = "480p"
    case unknown = "SD"
    
    public var sortOrder: Int {
        switch self {
        case .res4K: return 400
        case .res1080p: return 300
        case .res720p: return 200
        case .res480p: return 100
        case .unknown: return 0
        }
    }
    
    public static func < (lhs: VideoResolution, rhs: VideoResolution) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
    
    public static func parse(from rawTitle: String) -> VideoResolution {
        let lower = rawTitle.lowercased()
        if lower.contains("2160p") || lower.contains("4k") || lower.contains("uhd") {
            return .res4K
        } else if lower.contains("1080p") || lower.contains("fhd") {
            return .res1080p
        } else if lower.contains("720p") || lower.contains("hd") {
            return .res720p
        } else if lower.contains("480p") {
            return .res480p
        }
        return .unknown
    }
}

/// Release quality tier
public enum ReleaseQuality: String, Codable, Sendable, Comparable {
    case remux = "Remux"
    case bluray = "BluRay"
    case webdl = "WEB-DL"
    case hdtv = "HDTV"
    case cam = "CAM"
    case unknown = "Unknown"
    
    public var sortOrder: Int {
        switch self {
        case .remux: return 500
        case .bluray: return 400
        case .webdl: return 300
        case .hdtv: return 200
        case .cam: return 100
        case .unknown: return 0
        }
    }
    
    public static func < (lhs: ReleaseQuality, rhs: ReleaseQuality) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
    
    public static func parse(from rawTitle: String) -> ReleaseQuality {
        let upper = rawTitle.uppercased()
        if upper.contains("REMUX") { return .remux }
        if upper.contains("BLURAY") || upper.contains("BDRIP") || upper.contains("BRRIP") { return .bluray }
        if upper.contains("WEB-DL") || upper.contains("WEBRIP") || upper.contains("WEB") { return .webdl }
        if upper.contains("HDTV") { return .hdtv }
        if upper.contains("CAM") || upper.contains("TELESYNC") { return .cam }
        return .unknown
    }
}

/// Discovered source stream before resolution into a direct playback URL
public struct SourceStream: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let providerName: String
    public let resolution: VideoResolution
    public let quality: ReleaseQuality
    public let codec: String?          // e.g. "HEVC", "H.264", "AV1"
    public let audioCodec: String?     // e.g. "Atmos", "DDP 5.1", "AAC"
    public let sizeBytes: Int64?
    public let seeds: Int?
    public let isRealDebridCached: Bool // Instant cache on Real-Debrid
    public let magnetURL: String?
    public let infoHash: String?
    public let fileIndex: Int?         // Targeted file index within multi-file torrent
    public let originalFileName: String?
    public let providerId: String?
    public let cloudTorrentId: String?
    public let directURL: URL?
    public let targetSeason: Int?
    public let targetEpisode: Int?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        providerName: String,
        resolution: VideoResolution? = nil,
        quality: ReleaseQuality? = nil,
        codec: String? = nil,
        audioCodec: String? = nil,
        sizeBytes: Int64? = nil,
        seeds: Int? = nil,
        isRealDebridCached: Bool = false,
        magnetURL: String? = nil,
        infoHash: String? = nil,
        fileIndex: Int? = nil,
        originalFileName: String? = nil,
        providerId: String? = nil,
        cloudTorrentId: String? = nil,
        directURL: URL? = nil,
        targetSeason: Int? = nil,
        targetEpisode: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.providerName = providerName
        self.resolution = resolution ?? VideoResolution.parse(from: title)
        self.quality = quality ?? ReleaseQuality.parse(from: title)
        self.codec = codec ?? SourceStream.detectCodec(from: title)
        self.audioCodec = audioCodec ?? SourceStream.detectAudio(from: title)
        self.sizeBytes = sizeBytes
        self.seeds = seeds
        self.isRealDebridCached = isRealDebridCached
        self.magnetURL = magnetURL
        self.infoHash = infoHash ?? SourceStream.extractHash(from: magnetURL)
        self.fileIndex = fileIndex
        self.originalFileName = originalFileName
        self.providerId = providerId
        self.cloudTorrentId = cloudTorrentId
        self.directURL = directURL
        self.targetSeason = targetSeason
        self.targetEpisode = targetEpisode
    }
    
    public var formattedSize: String {
        guard let bytes = sizeBytes, bytes > 0 else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    public static func detectCodec(from text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("HEVC") || upper.contains("X265") || upper.contains("H.265") || upper.contains("H265") {
            return "HEVC"
        } else if upper.contains("X264") || upper.contains("H.264") || upper.contains("H264") || upper.contains("AVC") {
            return "H.264"
        } else if upper.contains("AV1") {
            return "AV1"
        }
        return nil
    }
    
    public static func detectAudio(from text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("ATMOS") {
            return "Dolby Atmos"
        } else if upper.contains("DDP5.1") || upper.contains("EAC3") || upper.contains("DD+ 5.1") {
            return "DDP 5.1"
        } else if upper.contains("AC3") || upper.contains("DD5.1") {
            return "DD 5.1"
        } else if upper.contains("DTS-HD") || upper.contains("DTS") {
            return "DTS"
        } else if upper.contains("AAC") {
            return "AAC"
        }
        return nil
    }
    
    public static func extractHash(from magnet: String?) -> String? {
        guard let input = magnet?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let candidate: String
        if let components = URLComponents(string: input), components.scheme?.lowercased() == "magnet" {
            guard let xt = components.queryItems?.first(where: {
                $0.name.lowercased() == "xt" && ($0.value?.lowercased().hasPrefix("urn:btih:") ?? false)
            })?.value else { return nil }
            candidate = String(xt.dropFirst(9))
        } else {
            candidate = input
        }
        let upper = candidate.uppercased()
        if upper.count == 40 && upper.allSatisfy({ "0123456789ABCDEF".contains($0) }) { return upper }
        // Decode the 32-character base32 representation of a v1 SHA1 info-hash.
        guard upper.count == 32 else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var accumulator = 0, bitCount = 0
        var bytes: [UInt8] = []
        for char in upper {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            accumulator = (accumulator << 5) | digit
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((accumulator >> bitCount) & 255))
                accumulator &= (1 << bitCount) - 1
            }
        }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    public static func normalizedMagnet(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = extractHash(from: trimmed) else { return nil }
        if URLComponents(string: trimmed)?.scheme?.lowercased() == "magnet" { return trimmed }
        return "magnet:?xt=urn:btih:\(hash)"
    }
}
