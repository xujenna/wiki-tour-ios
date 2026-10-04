import SwiftUI
import AVFoundation

/// The first-load screen: a full-screen version of the app icon. The docbotic.care sky video loops
/// under the icon's dark halftone, with the icon's shoe centered and progress beneath it. The system
/// launch screen (Info.plist) shows the same shoe on the sky's average color, so launch hands off
/// without a jump.
struct LoadingView: View {
    let caption: String

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            SkyVideo()
            HalftoneOverlay(color: Color(red: 0.1, green: 0.16, blue: 0.32).opacity(0.22), spacing: 4, dotSize: 1.4)
            Image("LoadingShoe") // 52 pt, its natural size: the largest that stays sharp.
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            // A regular spinner inline with the caption, as in the app's other loading states.
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(caption)
                    .mockFont(BundledFonts.textBold, size: 17)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            // Below the shoe, which is centered exactly as on the launch screen.
            .offset(y: 26 + 56)
        }
        .ignoresSafeArea()
        .fontDesign(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityIdentifier("loadingScreen")
    }
}

/// The bundled sky loop, muted and filling the screen. It mixes with other audio and never takes
/// over the user's music.
private struct SkyVideo: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerView {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: "SkyLoop", withExtension: "mp4") else { return view }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
