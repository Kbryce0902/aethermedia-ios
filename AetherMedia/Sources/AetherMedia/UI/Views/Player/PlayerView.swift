import SwiftUI
import UIKit
import AVKit

@MainActor
public struct PlayerView: View {
    public let stream: PlayableStream
    public let mediaItem: MediaItem
    public let episode: Episode?
    public let resumeSeconds: Double?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var playbackEngine: PlaybackEngine
    public init(stream: PlayableStream, mediaItem: MediaItem, episode: Episode? = nil,
                resumeSeconds: Double? = nil, playbackEngine: PlaybackEngine? = nil) {
        self.stream = stream
        self.mediaItem = mediaItem
        self.episode = episode
        self.resumeSeconds = resumeSeconds
        self.playbackEngine = playbackEngine ?? .shared
    }
    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let controller = playbackEngine.extendedController {
                ExtendedVideoPlayer(controller: controller).ignoresSafeArea()
            } else if let player = playbackEngine.player {
                NativeVideoPlayer(player: player).ignoresSafeArea()
            }
            if case .failed(let message) = playbackEngine.state {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(message).multilineTextAlignment(.center)
                    Button("Close Player") { dismiss() }.buttonStyle(.borderedProminent)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if playbackEngine.state == .loading || playbackEngine.state == .buffering {
                ProgressView("Loading stream…").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(14).background(.ultraThinMaterial).clipShape(Circle())
            }.accessibilityLabel("Close player").padding(16)
        }
        .foregroundStyle(.white)
        .onAppear { playbackEngine.loadAndPlay(stream: stream, mediaItem: mediaItem, episode: episode, startAtSeconds: resumeSeconds) }
        .onDisappear { playbackEngine.cleanupPlayer() }
    }
}

/// System controls provide working scrub, volume, audio/subtitle selection, AirPlay and PiP.
private struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
