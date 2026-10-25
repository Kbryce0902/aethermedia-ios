import Foundation

/// Fixed operation names deliberately exclude URLs, tokens, magnets and request bodies.
public enum RealDebridOperation: String, Sendable {
    case authorization = "Authorizing the account"
    case account = "Reading the account"
    case cloudLookup = "Checking the existing cloud"
    case torrentInfo = "Reading torrent files"
    case addSource = "Adding the source"
    case selectFile = "Selecting the requested file"
    case playbackLink = "Getting the playback link"
    case removeTorrent = "Removing a cloud entry"
    case other = "Contacting Real-Debrid"

    static func forPath(_ path: String) -> Self {
        if path == "user" { return .account }
        if path == "torrents" { return .cloudLookup }
        if path == "torrents/addMagnet" { return .addSource }
        if path.hasPrefix("torrents/info/") { return .torrentInfo }
        if path.hasPrefix("torrents/selectFiles/") { return .selectFile }
        if path.hasPrefix("torrents/delete/") { return .removeTorrent }
        if path == "unrestrict/link" { return .playbackLink }
        return .other
    }
}

public struct RealDebridRequestFailure: LocalizedError, Sendable, Equatable {
    public let operation: RealDebridOperation
    public let statusCode: Int
    public let code: Int?

    public init(operation: RealDebridOperation, statusCode: Int, code: Int?) {
        self.operation = operation
        self.statusCode = statusCode
        self.code = code
    }

    public var errorDescription: String? {
        let step = operation.rawValue.lowercased()
        if code == 35 {
            return "Real-Debrid refused this source while \(step). It reported ‘Infringing file’ (code 35)."
        }
        if code == 36 {
            return "Real-Debrid reported its fair usage limit while \(step). Check your account before retrying."
        }
        if code == 22 {
            return "Real-Debrid did not allow this network address while \(step). Check its account/network access settings."
        }
        if code == 24 {
            return "Real-Debrid reported that the file is unavailable while \(step)."
        }
        return "Real-Debrid rejected the request while \(step) (HTTP \(statusCode)\(code.map { ", code \($0)" } ?? ""))."
    }

    public var diagnosticDetails: String {
        "Step: \(operation.rawValue)\nHTTP: \(statusCode)\nReal-Debrid code: \(code.map(String.init) ?? "not supplied")"
    }
}

/// The structured DecodingError is preserved without its raw debugDescription,
/// underlying error, response values or network credentials.
public struct RealDebridDecodingFailure: LocalizedError, Sendable, Equatable {
    public let operation: RealDebridOperation
    public let codingPath: String
    public let reason: String
    public let expectedType: String

    public init(operation: RealDebridOperation, error: DecodingError) {
        self.operation = operation
        let keys: [any CodingKey]
        switch error {
        case .typeMismatch(let type, let context):
            keys = context.codingPath
            reason = "Type mismatch"; expectedType = String(reflecting: type)
        case .valueNotFound(let type, let context):
            keys = context.codingPath
            reason = "Null value"; expectedType = String(reflecting: type)
        case .keyNotFound(let key, let context):
            keys = context.codingPath + [key]
            reason = "Missing field"; expectedType = "Required response field"
        case .dataCorrupted(let context):
            keys = context.codingPath
            reason = "Invalid JSON or value"; expectedType = "Valid response data"
        @unknown default:
            keys = []
            reason = "Unreadable response"; expectedType = "Valid response data"
        }
        // These DTOs have fixed keys. Never print arbitrary dictionary keys or
        // DecodingError.debugDescription, which can contain account/file values.
        let allowed: Set<String> = ["id", "filename", "original_filename", "hash", "bytes", "host", "split",
            "progress", "status", "added", "links", "ended", "speed", "seeders", "files", "path", "selected",
            "download", "filesize", "mimeType", "chunks", "streamable", "link", "uri",
            "device_code", "user_code", "interval", "expires_in", "verification_url", "client_id", "client_secret",
            "access_token", "token_type", "refresh_token", "username", "email", "points", "type", "expiration"]
        codingPath = keys.prefix(16).reduce("$") { path, key in
            if let index = key.intValue { return path + "[\(index)]" }
            return path + "." + (allowed.contains(key.stringValue) ? key.stringValue : "<field>")
        }
    }

    public var errorDescription: String? {
        "Real-Debrid returned an unexpected data format while \(operation.rawValue.lowercased()). Response field: \(codingPath)."
    }
    public var diagnosticDetails: String {
        "Step: \(operation.rawValue)\nJSON path: \(codingPath)\nFailure: \(reason)\nExpected: \(expectedType)"
    }
}
