import XCTest
import AVFoundation
@testable import AetherMedia

final class PlaybackEngineTests: XCTestCase {
    @MainActor func testPlayerCreationAndCompleteCleanup() {
        let engine = PlaybackEngine()
        let media = MediaItem(id: "fixture", title: "Fixture")
        let episode = Episode(id: "fixture:1:1", seasonNumber: 1, episodeNumber: 1, title: "Episode")
        let stream = PlayableStream(streamURL: URL(fileURLWithPath: "/nonexistent-fixture.mp4"), title: "Fixture", filename: "fixture.mp4")
        XCTAssertNil(engine.player)
        engine.loadAndPlay(stream: stream, mediaItem: media, episode: episode)
        XCTAssertNotNil(engine.player)
        XCTAssertEqual(engine.currentMediaItem, media)
        XCTAssertEqual(engine.currentEpisode, episode)
        engine.cleanupPlayer()
        XCTAssertNil(engine.player)
        XCTAssertNil(engine.currentStream)
        XCTAssertNil(engine.currentMediaItem)
        XCTAssertNil(engine.currentEpisode)
        XCTAssertEqual(engine.state, .idle)
    }
    @MainActor func testUnsupportedContainerShowsFailureWithoutStartingPlayer() {
        let engine = PlaybackEngine()
        engine.loadAndPlay(stream: PlayableStream(streamURL: URL(fileURLWithPath: "/fixture.zip"), title: "Fixture", filename: "fixture.zip"), mediaItem: MediaItem(id: "fixture", title: "Fixture"))
        XCTAssertNil(engine.player)
        guard case .failed(let message) = engine.state else { return XCTFail("Expected format failure") }
        XCTAssertTrue(message.contains("archive"))
        engine.cleanupPlayer()
    }
    @MainActor func testSourceAudioMetadataIsRespectedForMP4() {
        let source = SourceStream(title: "Fixture.DTS", providerName: "Fixture", audioCodec: "DTS")
        let stream = PlayableStream(streamURL: URL(fileURLWithPath: "/fixture.mp4"), title: "Fixture", filename: "fixture.mp4").withOriginalSource(source)
        let engine = PlaybackEngine()
        engine.loadAndPlay(stream: stream, mediaItem: MediaItem(id: "fixture", title: "Fixture"))
        XCTAssertNil(engine.player)
        XCTAssertEqual(engine.activeEngine, .vlcKit)
        XCTAssertNotNil(engine.extendedController)
        engine.cleanupPlayer()
    }
    @MainActor func testExpiredStreamIsRejected() {
        let engine = PlaybackEngine()
        engine.loadAndPlay(stream: PlayableStream(streamURL: URL(fileURLWithPath: "/fixture.mp4"), title: "Fixture", filename: "fixture.mp4", expiresAt: .distantPast), mediaItem: MediaItem(id: "fixture", title: "Fixture"))
        XCTAssertNil(engine.player)
        guard case .failed(let message) = engine.state else { return XCTFail("Expected expired link failure") }
        XCTAssertTrue(message.contains("expired"))
        engine.cleanupPlayer()
    }
}
