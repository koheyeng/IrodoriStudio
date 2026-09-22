import AVFoundation
import Observation

/// アプリ全体で1つの再生機。別の音声を再生すると前のは止まる。
@MainActor
@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    /// 再生位置 0...1
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func isPlaying(_ url: URL) -> Bool {
        isPlaying && currentURL == url
    }

    /// 再生中なら止め、止まっていれば頭から再生する
    func toggle(_ url: URL) {
        if isPlaying(url) {
            stop()
        } else {
            play(url)
        }
    }

    func play(_ url: URL) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        currentURL = url
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        progress = 0
    }

    private func tick() {
        guard let player, player.duration > 0 else { return }
        progress = player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
