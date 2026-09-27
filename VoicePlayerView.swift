import SwiftUI
import AVFoundation

/// Плеер голосового сообщения: кнопка play/pause + длительность.
/// Играет напрямую по URL от MAX (AVPlayer умеет стримить), без скачивания.
struct VoicePlayerView: View {
    let url: URL
    let durationHint: Int?    // мс, из вложения — пока не проиграли, показываем его

    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var total: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button { toggle() } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(fraction))
                        }
                    }
                Text(timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 170)
        .onDisappear { cleanup() }
    }

    private var fraction: Double { total > 0 ? min(1, progress / total) : 0 }

    private var timeLabel: String {
        let secs = Int(total > 0 ? (playing || progress > 0 ? progress : total) : Double(durationHint ?? 0) / 1000)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private func toggle() {
        if player == nil {
            let p = AVPlayer(url: url)
            player = p
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { t in
                progress = t.seconds
                if let d = p.currentItem?.duration.seconds, d.isFinite { total = d }
            }
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
            ) { _ in
                playing = false
                progress = 0
                p.seek(to: .zero)
            }
        }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }

    private func cleanup() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
    }
}
