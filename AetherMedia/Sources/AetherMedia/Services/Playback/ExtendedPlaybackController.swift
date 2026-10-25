import Foundation
import UIKit
import VLCKit

public struct PlaybackTrack: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let selected: Bool
}

/// Real VideoLAN decoder for Matroska and formats outside AVPlayer's support.
@MainActor
public final class ExtendedPlaybackController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    public let videoView = UIView()
    @Published public private(set) var state: PlaybackState = .loading
    @Published public private(set) var currentSeconds: Double = 0
    @Published public private(set) var durationSeconds: Double = 0
    @Published public private(set) var audioTracks: [PlaybackTrack] = []
    @Published public private(set) var subtitleTracks: [PlaybackTrack] = []
    public var onStateChange: ((PlaybackState) -> Void)?
    public var onTimeUpdate: ((Double, Double) -> Void)?
    private let owner = VLCPlaybackOwner()
    private var player: VLCMediaPlayer { owner.player }
    private var pendingResume: Double?
    private var stopped = false
    private var didPlay = false
    public var hasVideoOutput: Bool { player.hasVideoOut }

    public init(stream: PlayableStream, resumeSeconds: Double? = nil) {
        pendingResume = resumeSeconds
        super.init()
        videoView.frame = UIScreen.main.bounds
        videoView.backgroundColor = .black
        videoView.clipsToBounds = true
        player.timeChangeUpdateInterval = 0.1
        player.minimalTimePeriod = 100_000
        player.delegate = self
        player.drawable = videoView
        guard let media = VLCMedia(url: stream.streamURL) else {
            state = .failed("The extended player could not open this media URL.")
            return
        }
        media.addOption(":network-caching=1500")
        player.media = media
    }
    public func play() {
        guard !stopped else { return }
        guard player.media != nil else { setState(.failed("The extended player could not open this media URL.")); return }
        player.play()
    }
    public func pause() { player.pause(); setState(.paused) }
    public func togglePlayPause() { state == .playing ? pause() : play() }
    public func seek(to seconds: Double) {
        guard !stopped, seconds.isFinite, durationSeconds > 0 else { return }
        let clamped = min(max(0, seconds), max(0, durationSeconds - 0.1))
        player.time = VLCTime(int: Int32(min(clamped * 1000, Double(Int32.max))))
    }
    public func selectAudio(id: String) {
        player.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
        refreshTracks()
    }
    public func selectSubtitle(id: String?) {
        if let id { player.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true }
        else { player.deselectAllTextTracks() }
        refreshTracks()
    }
    public func stop() {
        guard !stopped else { return }
        stopped = true
        player.delegate = nil
        player.stop()
        player.drawable = nil
        onStateChange = nil
        onTimeUpdate = nil
    }
    private func setState(_ value: PlaybackState) {
        guard !stopped else { return }
        state = value
        onStateChange?(value)
    }
    private func refreshTracks() {
        audioTracks = player.audioTracks.map { PlaybackTrack(id: $0.trackId, name: $0.trackName, selected: $0.isSelected) }
        subtitleTracks = player.textTracks.map { PlaybackTrack(id: $0.trackId, name: $0.trackName, selected: $0.isSelected) }
    }
    private func updateTime() {
        guard !stopped else { return }
        let total = Double(player.media?.length.intValue ?? 0) / 1000
        let current = Double(player.time.intValue) / 1000
        if total > 0 { durationSeconds = total }
        if current >= 0 { currentSeconds = current }
        if let resume = pendingResume, durationSeconds > 0 {
            pendingResume = nil
            seek(to: resume)
        }
        refreshTracks()
        if durationSeconds > 0 { onTimeUpdate?(currentSeconds, durationSeconds) }
    }
    nonisolated public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            switch newState {
            case .opening: self.setState(.loading)
            case .playing: self.didPlay = true; self.updateTime(); self.setState(.playing)
            case .paused: self.updateTime(); self.setState(.paused)
            case .error: self.setState(.failed("The extended player could not open this stream. It may be unavailable or expired; find streams again or select another source."))
            case .stopped:
                if self.didPlay && self.durationSeconds > 0 && self.currentSeconds >= self.durationSeconds - 1.5 { self.setState(.completed) }
            default: break
            }
        }
    }
    nonisolated public func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.updateTime() }
    }
    nonisolated public func mediaPlayerBufferingChanged(_ progress: Float) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, self.state != .paused else { return }
            if progress < 1 { self.setState(.buffering) }
            else if self.player.isPlaying { self.setState(.playing) }
        }
    }
}

/// Ensures decoder teardown does not read main-actor @Published properties in deinit.
private final class VLCPlaybackOwner {
    let player = VLCMediaPlayer()
    deinit { player.delegate = nil; player.stop(); player.drawable = nil }
}
