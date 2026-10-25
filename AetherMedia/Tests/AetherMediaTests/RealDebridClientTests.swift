import XCTest
@testable import AetherMedia

final class RealDebridClientTests: XCTestCase {
    var mockClient: MockRealDebridClient!
    var keychain: KeychainService!
    
    override func setUp() {
        super.setUp()
        keychain = KeychainService(isTesting: true)
        keychain.clearAll()
        mockClient = MockRealDebridClient(isAuthenticated: true, isPremium: true)
    }
    
    func testDeviceAuthorizationFlow() async throws {
        // Step 1: Request Device Code
        let codeResp = try await mockClient.requestDeviceCode()
        XCTAssertEqual(codeResp.userCode, "TEST9999")
        XCTAssertEqual(codeResp.verificationUrl, "https://real-debrid.com/device")
        XCTAssertGreaterThan(codeResp.expiresIn, 0)
        
        // Step 2: Poll for Credentials
        let creds = try await mockClient.pollForCredentials(deviceCode: codeResp.deviceCode)
        XCTAssertFalse(creds.clientId.isEmpty)
        XCTAssertFalse(creds.clientSecret.isEmpty)
        
        // Step 3: Exchange for Tokens
        let tokens = try await mockClient.exchangeCodeForToken(
            clientId: creds.clientId,
            clientSecret: creds.clientSecret,
            deviceCode: codeResp.deviceCode
        )
        XCTAssertEqual(tokens.accessToken, "mock_access_token_abcdef123456")
        XCTAssertTrue(mockClient.isAuthenticated)
    }
    
    func testUserProfileFetch() async throws {
        let user = try await mockClient.getUserProfile()
        XCTAssertEqual(user.username, "AetherTester")
        XCTAssertTrue(user.isPremium)
        XCTAssertEqual(user.points, 1540)
    }
    
    func testNonPremiumUserThrows() async {
        mockClient.isPremium = false
        do {
            _ = try await mockClient.unrestrictLink("https://real-debrid.com/d/MOCK01")
            XCTFail("Should throw accountNotPremium error")
        } catch RealDebridError.accountNotPremium {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRateLimitHandling() async {
        mockClient.simulateRateLimit = true
        do {
            _ = try await mockClient.getUserProfile()
            XCTFail("Should throw rateLimited error")
        } catch RealDebridError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testInstantAvailabilityLookup() async throws {
        let hashes = ["B41A41041A41041A41041A41041A41041A41041A"]
        let map = try await mockClient.checkInstantAvailability(hashes: hashes)
        XCTAssertNotNil(map[hashes[0]])
        XCTAssertTrue(map[hashes[0]]?.isCached == true)
    }
    
    func testUnrestrictLinkResolution() async throws {
        let unrestrict = try await mockClient.unrestrictLink("https://real-debrid.com/d/MOCK01")
        XCTAssertTrue(unrestrict.isStreamable)
        XCTAssertTrue(unrestrict.download.hasPrefix("https://"))
        XCTAssertEqual(unrestrict.mimeType, "video/mp4")
    }
    
    func testMagnetResolutionPipeline() async throws {
        let sampleMagnet = "magnet:?xt=urn:btih:B41A41041A41041A41041A41041A41041A41041A&dn=SampleVideo"
        let stream = try await mockClient.resolveMagnetToStream(magnet: sampleMagnet, preferredFileIndex: nil)
        XCTAssertEqual(stream.title, "Big Buck Bunny (Public Domain)")
        XCTAssertEqual(stream.mimeType, "video/mp4")
        XCTAssertFalse(stream.isExpired)
    }
    
    func testLogoutWipesAuthentication() {
        mockClient.logout()
        XCTAssertFalse(mockClient.isAuthenticated)
    }
}
