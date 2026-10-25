import SwiftUI
import UIKit

@MainActor
struct ExtendedVideoPlayer: View {
    @ObservedObject var controller: ExtendedPlaybackController
    @State private var showControls = true
    @State private var seeking = false
    @State private var seekValue: Double = 0
    var body: some View {
        ZStack {
            ExtendedVideoSurface(controller: controller).onTapGesture { showControls.toggle() }
            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 36) {
                        Button { controller.seek(to: controller.currentSeconds - 10) } label: { Image(systemName: "gobackward.10") }
                            .accessibilityLabel("Back ten seconds")
                        Button { controller.togglePlayPause() } label: { Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill") }
                            .accessibilityLabel(controller.state == .playing ? "Pause" : "Play")
                        Button { controller.seek(to: controller.currentSeconds + 10) } label: { Image(systemName: "goforward.10") }
                            .accessibilityLabel("Forward ten seconds")
                    }.font(.system(size: 30)).buttonStyle(.bordered).controlSize(.large)
                    Spacer()
                    VStack(spacing: 12) {
                        Slider(value: Binding(get: { seeking ? seekValue : min(controller.currentSeconds, max(1, controller.durationSeconds)) }, set: { seekValue = $0 }),
                               in: 0...max(1, controller.durationSeconds), onEditingChanged: { editing in
                            if editing { seekValue = controller.currentSeconds; seeking = true }
                            else { controller.seek(to: seekValue); seeking = false }
                        }).disabled(controller.durationSeconds <= 0).accessibilityLabel("Playback position")
                        HStack {
                            Text("\(format(controller.currentSeconds)) / \(format(controller.durationSeconds))").monospacedDigit()
                            Spacer()
                            Menu {
                                ForEach(controller.audioTracks) { track in
                                    Button { controller.selectAudio(id: track.id) } label: { Label(track.name, systemImage: track.selected ? "checkmark" : "speaker.wave.2") }
                                }
                            } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Audio tracks")
                            Menu {
                                Button("Off") { controller.selectSubtitle(id: nil) }
                                ForEach(controller.subtitleTracks) { track in
                                    Button { controller.selectSubtitle(id: track.id) } label: { Label(track.name, systemImage: track.selected ? "checkmark" : "captions.bubble") }
                                }
                            } label: { Image(systemName: "captions.bubble") }.accessibilityLabel("Subtitles")
                        }.font(.subheadline)
                    }.padding(20).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal,16).padding(.bottom,34)
                }.background(Color.black.opacity(0.2)).onTapGesture { showControls = false }
            }
        }.foregroundStyle(.white)
    }
    private func format(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let seconds = Int(value)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds/3600,(seconds/60)%60,seconds%60) : String(format: "%d:%02d",seconds/60,seconds%60)
    }
}
private struct ExtendedVideoSurface: UIViewRepresentable {
    let controller: ExtendedPlaybackController
    func makeUIView(context: Context) -> UIView { controller.videoView }
    func updateUIView(_ view: UIView, context: Context) {}
}
