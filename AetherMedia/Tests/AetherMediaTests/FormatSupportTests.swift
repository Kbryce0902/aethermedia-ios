import XCTest
@testable import AetherMedia

final class FormatSupportTests: XCTestCase {
    var evaluator: FormatSupportEvaluator!
    
    override func setUp() {
        super.setUp()
        evaluator = FormatSupportEvaluator()
    }
    
    func testNativeMP4Evaluation() {
        let assessment = evaluator.evaluate(
            filename: "BigBuckBunny.mp4",
            codec: "H.264",
            audioCodec: "AAC"
        )
        XCTAssertTrue(assessment.isNativelySupportedByAVPlayer)
        XCTAssertEqual(assessment.recommendedPlayer, .avPlayer)
        XCTAssertEqual(assessment.container, "MP4")
    }
    
    func testMKVWithDTSRequiresExtendedEngine() {
        let assessment = evaluator.evaluate(
            filename: "Movie.2160p.HDR.mkv",
            codec: "HEVC",
            audioCodec: "DTS-HD"
        )
        XCTAssertFalse(assessment.isNativelySupportedByAVPlayer)
        XCTAssertEqual(assessment.recommendedPlayer, .vlcKit)
    }
    
    func testArchiveRemainsRejected() {
        XCTAssertEqual(evaluator.evaluate(filename:"archive.zip",codec:nil,audioCodec:nil).recommendedPlayer,.unsupported)
    }

    func testUnknownFormatDoesNotClaimConfirmedSupport() {
        let assessment = evaluator.evaluate(filename: "video.unrecognized", codec: nil, audioCodec: nil)
        XCTAssertFalse(assessment.isNativelySupportedByAVPlayer)
    }

    func testSourceStreamDetectionHelpers() {
        let sampleTitle = "The.Dark.Knight.2008.2160p.UHD.BluRay.x265.10bit.HDR.DDP5.1.Atmos-Aether"
        let res = VideoResolution.parse(from: sampleTitle)
        XCTAssertEqual(res, .res4K)
        
        let codec = SourceStream.detectCodec(from: sampleTitle)
        XCTAssertEqual(codec, "HEVC")
        
        let audio = SourceStream.detectAudio(from: sampleTitle)
        XCTAssertEqual(audio, "Dolby Atmos")
        
        let magnet = "magnet:?xt=urn:btih:B41A41041A41041A41041A41041A41041A41041A&dn=DarkKnight"
        let hash = SourceStream.extractHash(from: magnet)
        XCTAssertEqual(hash, "B41A41041A41041A41041A41041A41041A41041A")
    }
}
