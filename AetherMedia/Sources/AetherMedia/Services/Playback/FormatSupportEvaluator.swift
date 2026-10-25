import Foundation

public struct MediaFormatAssessment: Sendable {
    public let container: String
    public let videoCodec: String
    public let audioCodec: String
    public let isNativelySupportedByAVPlayer: Bool
    public let recommendedPlayer: PlayerEngineType
    public let notes: String
}
public enum PlayerEngineType: String, Sendable {
    case avPlayer = "Native AVPlayer"
    case unsupported = "Unsupported archive"
    case vlcKit = "VideoLAN Extended Player"
}
public final class FormatSupportEvaluator: Sendable {
    public static let shared = FormatSupportEvaluator()
    public init() {}
    public func evaluate(filename: String, codec: String?, audioCodec: String?) -> MediaFormatAssessment {
        let ext = (filename as NSString).pathExtension.lowercased()
        let video = codec?.uppercased() ?? "UNKNOWN"
        let audio = audioCodec?.uppercased() ?? "UNKNOWN"
        let archive = ["iso", "rar", "zip", "7z"].contains(ext)
        let extended = ["mkv", "avi", "webm", "wmv", "flv", "ts", "m2ts", "mpeg", "mpg"].contains(ext)
            || audio.contains("DTS") || audio.contains("TRUEHD") || video.contains("XVID") || video.contains("DIVX")
        let knownNative = ["mp4", "m4v", "mov", "m3u8"].contains(ext) && !extended && !archive
            && ["H.264", "H264", "AVC", "HEVC", "H.265", "H265"].contains(video)
        return MediaFormatAssessment(container: ext.uppercased(), videoCodec: video, audioCodec: audio,
                                     isNativelySupportedByAVPlayer: knownNative, recommendedPlayer: archive ? .unsupported : (extended ? .vlcKit : .avPlayer),
                                     notes: archive ? "Select an extracted video file rather than an archive or disc image."
                                        : extended ? "Plays with the bundled VideoLAN decoder."
                                        : "AVPlayer will check this stream at playback time; codec profile and device support can vary.")
    }
}
