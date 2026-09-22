import AVFoundation
import IrodoriKit
import SwiftUI

/// 再生／停止ボタン。アプリ共通の AudioPlayer を使う。
struct PlayButton: View {
    let url: URL?
    var size: CGFloat = 22
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let playing = url.map(player.isPlaying) ?? false
        Button {
            if let url { player.toggle(url) }
        } label: {
            Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(url == nil ? Color.secondary.opacity(0.4) : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .help(playing ? "停止" : "再生")
    }
}

/// 波形。再生中はその位置まで色が付く。
struct WaveformView: View {
    let url: URL?
    var barCount = 64
    @Environment(AudioPlayer.self) private var player
    @State private var peaks: [Float] = []

    var body: some View {
        let playedFraction = (url != nil && player.currentURL == url && player.isPlaying) ? player.progress : 0
        GeometryReader { geometry in
            let barWidth = geometry.size.width / CGFloat(max(barCount, 1))
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(displayPeaks.enumerated()), id: \.offset) { index, peak in
                    let played = Double(index) / Double(barCount) < playedFraction
                    Capsule()
                        .fill(played ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: max(barWidth - 1.5, 1), height: max(2, geometry.size.height * CGFloat(peak)))
                        .frame(width: barWidth)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: url) {
            guard let url else { peaks = []; return }
            peaks = await WaveformCache.shared.peaks(for: url, count: barCount)
        }
    }

    private var displayPeaks: [Float] {
        peaks.isEmpty ? Array(repeating: 0.05, count: barCount) : peaks
    }
}

/// 波形の山を一度だけ読んで覚えておく
@MainActor
final class WaveformCache {
    static let shared = WaveformCache()
    private var cache: [String: [Float]] = [:]

    func peaks(for url: URL, count: Int) async -> [Float] {
        let key = "\(url.path)#\(count)"
        if let cached = cache[key] { return cached }
        let peaks = await Task.detached { Self.readPeaks(url: url, count: count) }.value
        cache[key] = peaks
        return peaks
    }

    nonisolated static func readPeaks(url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let chunk = max(frames / count, 1)
        var peaks: [Float] = []
        for bar in 0..<count {
            let start = bar * chunk
            let end = min(start + chunk, frames)
            guard start < end else { peaks.append(0); continue }
            var peak: Float = 0
            for i in start..<end { peak = max(peak, abs(samples[i])) }
            peaks.append(peak)
        }
        let loudest = peaks.max() ?? 1
        return peaks.map { loudest > 0 ? $0 / loudest : 0 }
    }
}

/// 生成状態のバッジ（未生成・待機中・生成中・生成済み・失敗）
struct StatusBadge: View {
    let status: LineStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .generating(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
            default:
                Image(systemName: symbol)
            }
            Text(status.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .help(helpText)
    }

    private var symbol: String {
        switch status {
        case .notGenerated: return "circle.dashed"
        case .queued: return "clock"
        case .generating: return "waveform"
        case .generated: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .notGenerated: return .secondary
        case .queued: return .orange
        case .generating: return .accentColor
        case .generated: return .green
        case .failed: return .red
        }
    }

    private var helpText: String {
        if case .failed(let message) = status { return message }
        return status.label
    }
}

/// 登場キャラの色
enum CastColor {
    static let palette: [Color] = [.pink, .orange, .blue, .teal, .purple, .green, .indigo, .brown]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }
}

extension TimeInterval {
    /// 「6.2秒」
    var secondsLabel: String { String(format: "%.1f秒", self) }
}
