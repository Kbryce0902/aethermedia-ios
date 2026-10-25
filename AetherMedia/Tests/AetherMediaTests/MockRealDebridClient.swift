import Foundation
@testable import AetherMedia

/// Deterministic mock Real-Debrid client for unit testing, previews, and offline scenarios
public final class MockRealDebridClient: RealDebridClientProtocol, @unchecked Sendable {
    public var isAuthenticated: Bool
    public var isPremium: Bool
    public var simulateRateLimit: Bool
    public var simulateExpiredToken: Bool
    public var sampleTorrents: [RDTorrent]
    
    // Public domain test streams
    public static let sampleBigBuckBunnyStream = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
    public static let sampleTearsOfSteelStream = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"
    
    public init(
        isAuthenticated: Bool = true,
        isPremium: Bool = true,
        simulateRateLimit: Bool = false,
        simulateExpiredToken: Bool = false
    ) {
        self.isAuthenticated = isAuthenticated
        self.isPremium = isPremium
        self.simulateRateLimit = simulateRateLimit
        self.simulateExpiredToken = simulateExpiredToken
        
        self.sampleTorrents = [
            RDTorrent(
                id: "MOCK_TORRENT_01",
                filename: "Big.Buck.Bunny.2008.2160p.HDR.x265-Aether.mkv",
                hash: "B41A41041A41041A41041A41041A41041A41041A",
                bytes: 1_288_490_188,
                host: "real-debrid.com",
                split: 1,
                progress: 100.0,
                status: "downloaded",
                added: "2026-10-24T12:00:00Z",
                links: ["https://real-debrid.com/d/MOCK01"],
                ended: "2026-10-24T12:01:00Z",
                speed: 0,
                seeders: 120
            ),
            RDTorrent(
                id: "MOCK_TORRENT_02",
                filename: "Tears.of.Steel.2012.1080p.BluRay.x264-Aether.mp4",
                hash: "C52B52052B52052B52052B52052B52052B52052B",
                bytes: 754_188_288,
                host: "real-debrid.com",
                split: 1,
                progress: 100.0,
                status: "downloaded",
                added: "2026-10-24T13:00:00Z",
                links: ["https://real-debrid.com/d/MOCK02"],
                ended: "2026-10-24T13:02:00Z",
                speed: 0,
                seeders: 85
            )
        ]
    }
    
    public func requestDeviceCode() async throws -> RDDeviceCodeResponse {
        RDDeviceCodeResponse(
            deviceCode: "MOCK_DEV_CODE_XYZ123",
            userCode: "TEST9999",
            interval: 1,
            expiresIn: 600,
            verificationUrl: "https://real-debrid.com/device"
        )
    }
    
    public func pollForCredentials(deviceCode: String) async throws -> RDCredentialsResponse {
        RDCredentialsResponse(
            clientId: "MOCK_CLIENT_ID",
            clientSecret: "MOCK_CLIENT_SECRET"
        )
    }
    
    public func exchangeCodeForToken(clientId: String, clientSecret: String, deviceCode: String) async throws -> RDTokenResponse {
        self.isAuthenticated = true
        return RDTokenResponse(
            accessToken: "mock_access_token_abcdef123456",
            expiresIn: 3600,
            tokenType: "Bearer",
            refreshToken: "mock_refresh_token_xyz987"
        )
    }
    
    public func refreshToken() async throws {
        if !isAuthenticated { throw RealDebridError.notAuthorized }
    }
    
    public func getUserProfile() async throws -> RDUser {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        if simulateRateLimit { throw RealDebridError.rateLimited(retryAfter: 2) }
        
        return RDUser(
            id: 999888,
            username: "AetherTester",
            email: "tester@aether.local",
            points: 1540,
            type: isPremium ? "premium" : "free",
            expiration: "2027-12-31T23:59:59.000Z"
        )
    }
    
    public func logout() {
        self.isAuthenticated = false
    }
    
    public func getTorrents(offset: Int, limit: Int) async throws -> [RDTorrent] {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        return sampleTorrents
    }
    
    public func getTorrentInfo(id: String) async throws -> RDTorrentInfo {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        return RDTorrentInfo(
            id: id,
            filename: "Big.Buck.Bunny.2008.2160p.HDR.x265-Aether.mkv",
            originalFilename: "Big.Buck.Bunny.2008.2160p.HDR.x265-Aether.mkv",
            hash: "B41A41041A41041A41041A41041A41041A41041A",
            bytes: 1_288_490_188,
            host: "real-debrid.com",
            progress: 100.0,
            status: "downloaded",
            added: "2026-10-24T12:00:00Z",
            files: [
                RDTorrentFile(id: 1, path: "/Big.Buck.Bunny.2008.2160p.mkv", bytes: 1_288_490_188, selected: 1),
                RDTorrentFile(id: 2, path: "/Sample.nfo", bytes: 1024, selected: 0)
            ],
            links: ["https://real-debrid.com/d/MOCK01"],
            ended: "2026-10-24T12:01:00Z",
            speed: 0,
            seeders: 120
        )
    }
    
    public func addMagnet(_ magnet: String) async throws -> String {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        return "MOCK_TORRENT_03"
    }
    
    public func selectFiles(torrentId: String, fileIds: [Int]?) async throws {
        // Mock successful file selection
    }
    
    public func checkInstantAvailability(hashes: [String]) async throws -> [String: RDInstantAvailability] {
        var result: [String: RDInstantAvailability] = [:]
        for hash in hashes {
            // By default mock that all requested hashes are cached on RD
            result[hash.uppercased()] = RDInstantAvailability(hash: hash.uppercased(), isCached: true)
        }
        return result
    }
    
    public func deleteTorrent(id: String) async throws {
        sampleTorrents.removeAll { $0.id == id }
    }
    
    public func unrestrictLink(_ link: String) async throws -> RDUnrestrictResponse {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        guard isPremium else { throw RealDebridError.accountNotPremium }
        
        let sampleURL = link.contains("MOCK02") ? Self.sampleTearsOfSteelStream : Self.sampleBigBuckBunnyStream
        
        return RDUnrestrictResponse(
            id: "UNRESTRICT_\(UUID().uuidString.prefix(6))",
            filename: "Big.Buck.Bunny.2008.2160p.HDR.x265.mp4",
            mimeType: "video/mp4",
            filesize: 1_288_490_188,
            link: link,
            host: "real-debrid.com",
            chunks: 16,
            download: sampleURL,
            streamable: 1
        )
    }
    
    public func resolveMagnetToStream(magnet: String, preferredFileIndex: Int?) async throws -> PlayableStream {
        guard isAuthenticated else { throw RealDebridError.notAuthorized }
        guard isPremium else { throw RealDebridError.accountNotPremium }
        
        let directURL = URL(string: Self.sampleBigBuckBunnyStream)!
        return PlayableStream(
            streamURL: directURL,
            title: "Big Buck Bunny (Public Domain)",
            filename: "BigBuckBunny.mp4",
            mimeType: "video/mp4",
            fileSize: 1_288_490_188
        )
    }
}
