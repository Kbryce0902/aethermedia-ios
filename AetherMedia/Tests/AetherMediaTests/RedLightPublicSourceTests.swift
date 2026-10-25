import XCTest
import Foundation
@testable import AetherMedia

/// Optional real HTTP test of the production source client, using Blender's public CC film.
/// It does not authorize, add to, inspect or change a Real-Debrid account.
final class RedLightPublicSourceTests: XCTestCase {
    func testPublicFilmDiscoveryUsingRealServices() async throws {
        guard ProcessInfo.processInfo.environment["AETHERMEDIA_SOURCE_LIVE"] == "1" else {
            throw XCTSkip("Public source service check is opt-in and runs separately from isolated tests.")
        }
        var config = RedLightConfiguration()
        config.enabled = [.comet, .mediafusion, .zilean, .torz, .torrentio, .piratebay, .torrentdownloads]
        let fixed = config
        let client = RedLightSourceClient(configuration: { fixed })
        let result = try await client.discover(for: MediaItem(id: "tt1254207", title: "Big Buck Bunny", releaseYear: 2008, imdbId: "tt1254207"), episode: nil)
        let report = PublicSourceReport(realNetwork: true, simulatedResponses: false, accountUsed: false,
            fixture: "Blender Big Buck Bunny (2008), Creative Commons", reports: result.reports,
            acceptedSources: result.sources.count, scope: "Public source discovery only; no account resolution or player test.")
        if let output = ProcessInfo.processInfo.environment["AETHERMEDIA_SOURCE_REPORT"] {
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
        }
        for report in result.reports {
            print("Red Light public check: \(report.name), \(report.status), \(report.accepted) accepted")
        }
        XCTAssertEqual(result.reports.count, 7)
        XCTAssertGreaterThan(result.sources.count, 0, "No enabled real service returned an accepted public fixture source.")
    }
}
private struct PublicSourceReport: Encodable {
    let realNetwork: Bool
    let simulatedResponses: Bool
    let accountUsed: Bool
    let fixture: String
    let reports: [SourceBackendReport]
    let acceptedSources: Int
    let scope: String
}
