import AVFoundation
import Foundation

/// 使う音声合成モデル。設定画面で切り替える。
public enum TTSModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case small
    case anime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return "本家 v4.1-Small"
        case .anime: return "Anime版 v4.1-Anime"
        }
    }

    public var repoID: String {
        switch self {
        case .small: return "Aratako/Irodori-TTS-v4.1-Small"
        case .anime: return "phasefield-audio/Irodori-TTS-v4.1-Anime"
        }
    }
}

/// 1本焼くための指示
public struct SynthesisRequest: Hashable, Sendable {
    /// セリフ（絵文字の演技指導を含む）
    public var text: String
    /// キャプション。nil ならキャプション無し
    public var caption: String?
    public var seed: Int
    /// 声を固定する参照音声。nil なら参照なし（no_ref）
    public var referenceAudioURL: URL?

    public init(text: String, caption: String?, seed: Int, referenceAudioURL: URL? = nil) {
        self.text = text
        self.caption = caption
        self.seed = seed
        self.referenceAudioURL = referenceAudioURL
    }
}

/// セリフの長さの目安。1回の生成は30秒までなので、長いセリフは句点で70〜150字ずつに切ると安定する。
public enum LineLength {
    public static let recommendedMax = 150
    public static let warning = "150字を超えています。句点で70〜150字ずつに分けると安定します（1回の生成は30秒まで）"
}

public struct SynthesisResult: Hashable, Sendable {
    /// 焼き上がった wav
    public var audioURL: URL
    public var duration: TimeInterval

    public init(audioURL: URL, duration: TimeInterval) {
        self.audioURL = audioURL
        self.duration = duration
    }
}

/// 音声合成エンジン。Phase 1 はモック、Phase 2 で Python の常駐ワーカーに繋いだ実装に差し替える。
///
/// MPS は同時に複数の生成を走らせられないので、呼ぶ側が1本ずつ順番に呼ぶこと。
public protocol SpeechSynthesizer: Sendable {
    /// モデルを読み込む。本物は初回 約40秒、2回目以降 約5秒かかる。
    func prepare(model: TTSModel) async throws
    /// 1本焼く。progress には 0...1 を渡す。キャンセルされたら CancellationError を投げる。
    func synthesize(
        _ request: SynthesisRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SynthesisResult
}

/// 偽の待ち時間で、手元のダミー音声を返すモック。
public struct MockSpeechSynthesizer: SpeechSynthesizer {
    /// ダミー音声の置き場（中の wav を使い回す）
    public let dummyAudioDirectory: URL
    /// 焼いた音声のコピー先
    public let outputDirectory: URL

    public init(dummyAudioDirectory: URL, outputDirectory: URL) {
        self.dummyAudioDirectory = dummyAudioDirectory
        self.outputDirectory = outputDirectory
    }

    public func prepare(model: TTSModel) async throws {
        try await Task.sleep(for: .seconds(1.5))
    }

    public func synthesize(
        _ request: SynthesisRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SynthesisResult {
        // 本物は6秒の音声が4〜5秒。モックは待ちすぎない程度に、セリフの長さで少し伸ばす
        let total = min(4.0, 1.5 + Double(request.text.count) * 0.03)
        let steps = 20
        for step in 1...steps {
            try await Task.sleep(for: .seconds(total / Double(steps)))
            progress(Double(step) / Double(steps))
        }

        let source = try pickDummy(for: request)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = Self.fileStamp.string(from: .now)
        let destination = outputDirectory.appendingPathComponent("\(stamp)_seed\(request.seed)_\(UUID().uuidString.prefix(6)).wav")
        try FileManager.default.copyItem(at: source, to: destination)
        return SynthesisResult(audioURL: destination, duration: Self.duration(of: destination))
    }

    /// キャプションとセリフの言葉から、それっぽいダミーを選ぶ。当てはまらなければ seed で決める。
    func pickDummy(for request: SynthesisRequest) throws -> URL {
        let files = try FileManager.default
            .contentsOfDirectory(at: dummyAudioDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw MockError.noDummyAudio(dummyAudioDirectory) }

        let haystack = (request.caption ?? "") + request.text
        for (keywords, name) in Self.keywordTable where keywords.contains(where: haystack.contains) {
            if let match = files.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
                return match
            }
        }
        return files[abs(request.seed) % files.count]
    }

    static let keywordTable: [([String], String)] = [
        (["男性", "青年", "少年", "男の子"], "c08_dansei"),
        (["泣", "😭"], "c05_naki"),
        (["怒", "😠"], "c07_ikari"),
        (["息切れ", "🌬️", "🥵"], "c10_ikigire"),
        (["囁", "👂"], "c04_sasayaki"),
        (["吐息", "🫶"], "adopt2_breathy"),
        (["ハスキー"], "adopt1_husky"),
        (["甘やか", "おっとり", "大人の女性"], "c09_mama"),
        (["からか", "いたずら", "😏", "🤭"], "c03_karakai"),
        (["クール", "淡々"], "c06_cool"),
        (["元気", "ハキハキ"], "c02_genki"),
    ]

    public static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    public enum MockError: LocalizedError {
        case noDummyAudio(URL)

        public var errorDescription: String? {
            switch self {
            case .noDummyAudio(let url): return "ダミー音声が見つかりません: \(url.path)"
            }
        }
    }
}
