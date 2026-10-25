import Foundation
import AVFoundation
import AVKit
import Combine

public enum PlaybackState: Sendable, Equatable {
    case idle, loading, playing, paused, buffering, completed
    case failed(String)
}

/// AVPlayer and all published playback state are confined to the main actor.
@MainActor
public final class PlaybackEngine: NSObject, ObservableObject {
    public static let shared = PlaybackEngine()
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var extendedController: ExtendedPlaybackController?
    @Published public private(set) var activeEngine: PlayerEngineType = .avPlayer
    @Published public private(set) var state: PlaybackState = .idle
    public private(set) var currentStream: PlayableStream?
    public private(set) var currentMediaItem: MediaItem?
    public private(set) var currentEpisode: Episode?
    public var onStateChange: ((PlaybackState) -> Void)?
    public var onTimeUpdate: ((Double, Double) -> Void)?
    private let persistence: PersistenceServiceProtocol
    private var timeObservation: PlaybackTimeObservation?
    private var cancellables = Set<AnyCancellable>()
    private var audioCancellables = Set<AnyCancellable>()
    private var progressTask: Task<Void, Never>?
    private var lastRecordedSecond: Double = 0
    private var wasPlayingBeforeInterruption = false

    public init(persistence: PersistenceServiceProtocol = PersistenceService.shared) {
        self.persistence = persistence
        super.init()
        setupNotifications()
    }
    private func setState(_ newState: PlaybackState) {
        state = newState
        onStateChange?(newState)
    }
    private func activateAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch { setState(.failed("The audio session could not be activated. Try playing again.")) }
        #endif
    }
    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor [weak self] in
                    guard let self, let raw = type, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                    switch type {
                    case .began:
                        self.wasPlayingBeforeInterruption = self.state == .playing
                        self.pause()
                    case .ended:
                        if self.wasPlayingBeforeInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.play() }
                        self.wasPlayingBeforeInterruption = false
                    @unknown default: break
                    }
                }
            }.store(in: &audioCancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    Task { @MainActor [weak self] in self?.pause() }
                }
            }.store(in: &audioCancellables)
        #endif
    }
    public func loadAndPlay(stream: PlayableStream, mediaItem: MediaItem, episode: Episode? = nil, startAtSeconds: Double? = nil) {
        cleanupPlayer()
        guard !stream.isExpired else { setState(.failed("The stream link expired. Find streams again.")); return }
        let assessment = FormatSupportEvaluator.shared.evaluate(filename: stream.filename,
                        codec: stream.originalSource?.codec, audioCodec: stream.originalSource?.audioCodec)
        guard assessment.recommendedPlayer != .unsupported else { setState(.failed(assessment.notes)); return }
        currentStream = stream
        currentMediaItem = mediaItem
        currentEpisode = episode
        setState(.loading)
        if assessment.recommendedPlayer == .vlcKit {
            startExtendedPlayer(stream: stream, resumeSeconds: startAtSeconds)
            return
        }
        activeEngine = .avPlayer
        let item = AVPlayerItem(url: stream.streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self, weak item] status in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player?.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    if let start = startAtSeconds, start.isFinite, start > 0 {
                        self.seek(to: start)
                    }
                    self.play()
                case .failed:
                    if let stream = self.currentStream {
                        let position = self.player?.currentTime().seconds ?? 0
                        self.startExtendedPlayer(stream: stream, resumeSeconds: position.isFinite && position > 0 ? position : startAtSeconds)
                    }
                default: break
                }
            }
        }.store(in: &cancellables)
        newPlayer.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main).sink { [weak self, weak newPlayer] status in
            Task { @MainActor [weak self, weak newPlayer] in
                guard let self, let newPlayer, self.player === newPlayer else { return }
                switch status {
                case .playing: self.setState(.playing)
                case .waitingToPlayAtSpecifiedRate: self.setState(.buffering)
                case .paused:
                    if self.state == .playing || self.state == .buffering { self.setState(.paused) }
                @unknown default: break
                }
            }
        }.store(in: &cancellables)
        let timeToken = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak newPlayer] time in
            Task { @MainActor [weak self, weak newPlayer] in
                guard let self, let player = newPlayer, self.player === player else { return }
                let duration = player.currentItem?.duration.seconds ?? 0
                guard time.seconds.isFinite, duration.isFinite, duration > 0 else { return }
                self.onTimeUpdate?(time.seconds, duration)
                self.recordProgress(force: false)
            }
        }
        timeObservation = PlaybackTimeObservation(player: newPlayer, token: timeToken)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player?.currentItem === item else { return }
                    self.setState(.completed)
                    guard let media = self.currentMediaItem else { return }
                    let id = media.id + (self.currentEpisode.map { "_\($0.id)" } ?? "")
                    let persistence = self.persistence
                    let previous = self.progressTask
                    self.progressTask = Task { await previous?.value; await persistence.clearProgress(id: id) }
                }
            }.store(in: &cancellables)
    }
    private func startExtendedPlayer(stream: PlayableStream, resumeSeconds: Double?) {
        guard extendedController == nil else { return }
        timeObservation = nil
        cancellables.removeAll()
        player?.pause()
        player = nil
        activeEngine = .vlcKit
        setState(.loading)
        let controller = ExtendedPlaybackController(stream: stream, resumeSeconds: resumeSeconds)
        controller.onStateChange = { [weak self, weak controller] value in
            guard let self, let controller, self.extendedController === controller else { return }
            self.setState(value)
            if value == .completed { self.clearCompletedProgress() }
        }
        controller.onTimeUpdate = { [weak self, weak controller] current, duration in
            guard let self, let controller, self.extendedController === controller else { return }
            self.onTimeUpdate?(current, duration)
            self.recordProgress(force: false)
        }
        extendedController = controller
        activateAudioSession()
        controller.play()
    }
    private func clearCompletedProgress() {
        guard let media = currentMediaItem else { return }
        let id = media.id + (currentEpisode.map { "_\($0.id)" } ?? "")
        let persistence = self.persistence, previous = progressTask
        progressTask = Task { await previous?.value; await persistence.clearProgress(id: id) }
    }
    public func play() {
        guard player != nil || extendedController != nil else { return }
        activateAudioSession()
        if let extendedController { extendedController.play() } else { player?.play() }
    }
    public func pause() {
        guard player != nil || extendedController != nil else { return }
        if let extendedController { extendedController.pause() } else { player?.pause() }
        if state != .completed { setState(.paused) }
        recordProgress(force: true)
    }
    public func togglePlayPause() { state == .playing ? pause() : play() }
    public func seek(to seconds: Double) {
        if let extendedController { extendedController.seek(to: seconds); return }
        guard seconds.isFinite, let player else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = duration.isFinite && duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    public func skipForward(by seconds: Double = 10) { seek(to: (extendedController?.currentSeconds ?? player?.currentTime().seconds ?? 0) + seconds) }
    public func skipBackward(by seconds: Double = 10) { seek(to: (extendedController?.currentSeconds ?? player?.currentTime().seconds ?? 0) - seconds) }
    private func recordProgress(force: Bool) {
        guard state != .completed, let media = currentMediaItem else { return }
        let current = extendedController?.currentSeconds ?? player?.currentTime().seconds ?? 0
        let duration = extendedController?.durationSeconds ?? player?.currentItem?.duration.seconds ?? 0
        guard current.isFinite, duration.isFinite, duration > 0,
              force || abs(current - lastRecordedSecond) >= 5 else { return }
        lastRecordedSecond = current
        let progress = UserWatchProgress(mediaItemId: media.id, mediaTitle: media.title, mediaType: media.type,
                        posterURL: media.posterURL, backdropURL: media.backdropURL, episodeId: currentEpisode?.id,
                        episodeCode: currentEpisode?.code, episodeTitle: currentEpisode?.title,
                        positionSeconds: max(0, current), durationSeconds: duration, isCompleted: current / duration >= 0.92)
        let persistence = self.persistence
        let previous = progressTask
        progressTask = Task { await previous?.value; await persistence.saveProgress(progress) }
    }
    public func cleanupPlayer() {
        recordProgress(force: true)
        extendedController?.stop()
        extendedController = nil
        activeEngine = .avPlayer
        timeObservation = nil
        cancellables.removeAll()
        player?.pause()
        player = nil
        currentStream = nil
        currentMediaItem = nil
        currentEpisode = nil
        lastRecordedSecond = 0
        setState(.idle)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// Owns exactly one AVPlayer observation without touching actor-isolated published state
/// during engine destruction. Explicit cleanup still releases this holder on the main actor.
private final class PlaybackTimeObservation {
    private let player: AVPlayer
    private let token: Any
    init(player: AVPlayer, token: Any) { self.player = player; self.token = token }
    deinit { player.removeTimeObserver(token) }
}
