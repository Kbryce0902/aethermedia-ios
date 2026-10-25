import XCTest
import UIKit
@testable import AetherMedia

final class ExtendedPlaybackTests: XCTestCase {
    @MainActor func testActualMatroskaAACDecodesWithVideoOutput() async throws { try await verifyPlayback(fixture:"mkv-aac") }
    @MainActor func testActualMatroskaDTSDecodesWithVideoOutput() async throws { try await verifyPlayback(fixture:"mkv-dts") }
    @MainActor private func verifyPlayback(fixture: String) async throws {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:fixture,withExtension:"mkv"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = PersistenceService(customStorageDirectory:directory)
        let engine = PlaybackEngine(persistence:persistence)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene:scene)
        let host = UIViewController();window.rootViewController=host;window.makeKeyAndVisible()
        defer { engine.cleanupPlayer();window.isHidden=true;try? FileManager.default.removeItem(at:directory) }
        engine.loadAndPlay(stream:PlayableStream(streamURL:url,title:fixture,filename:fixture+".mkv"),mediaItem:MediaItem(id:fixture,title:fixture))
        XCTAssertEqual(engine.activeEngine,.vlcKit)
        let extended = try XCTUnwrap(engine.extendedController)
        extended.videoView.frame=CGRect(x:0,y:0,width:320,height:180)
        host.view.addSubview(extended.videoView)
        var didDecode=false
        for _ in 0..<160 {
            if extended.hasVideoOutput && extended.currentSeconds > 0.05 { didDecode=true;break }
            if case .failed(let message)=engine.state { XCTFail(message);break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertTrue(didDecode,"The actual MKV fixture must produce decoded video and advancing time.")
        XCTAssertGreaterThan(extended.durationSeconds,0)
        engine.pause()
        XCTAssertEqual(engine.state,.paused)
        engine.cleanupPlayer()
        XCTAssertNil(engine.extendedController)
    }
}
