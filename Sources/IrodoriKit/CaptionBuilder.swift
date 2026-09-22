import Foundation

/// 声の設定から、Irodori-TTS に渡すキャプション（日本語の自然文）を組み立てる。
///
/// 例: 女性・10代・[優しい, いたずらっぽい]・高め →
/// 「高めで優しくていたずらっぽい声の少女。柔らかく穏やかに、少しからかうように話す。」
public enum CaptionBuilder {
    /// - Parameter includeVoiceQuality: false にすると声質（1文目）を入れず、話し方だけにする。
    ///   声の見本を参照音声として固定したときは声質を参照音声に任せる（両方で指定するとぶつかる）。
    public static func build(from settings: VoiceSettings, includeVoiceQuality: Bool = true) -> String {
        var sentences: [String] = []
        if includeVoiceQuality, let quality = qualitySentence(settings) {
            sentences.append(quality)
        }
        if let manner = mannerSentence(settings) {
            sentences.append(manner)
        }
        return sentences.joined()
    }

    static func qualitySentence(_ settings: VoiceSettings) -> String? {
        let moods = settings.orderedMoods
        var parts: [String] = []
        switch settings.pitch {
        case .high: parts.append(moods.isEmpty ? "高めの" : "高めで")
        case .low: parts.append(moods.isEmpty ? "低めの" : "低めで")
        case .normal: break
        }
        for (index, mood) in moods.enumerated() {
            parts.append(index == moods.count - 1 ? mood.attributive : mood.connective)
        }
        let noun = settings.age.personNoun(for: settings.gender)

        switch (parts.isEmpty, noun) {
        case (true, nil): return nil
        case (true, let noun?): return "\(noun)の声。"
        case (false, nil): return parts.joined() + "声。"
        case (false, let noun?): return parts.joined() + "声の\(noun)。"
        }
    }

    static func mannerSentence(_ settings: VoiceSettings) -> String? {
        let manners = settings.orderedMoods.compactMap(\.manner)
        guard !manners.isEmpty else { return nil }
        return manners.joined(separator: "、") + "話す。"
    }
}
