import Foundation

/// 性別。キャプションの人物の言い方（少女／少年など）に効く。
public enum Gender: String, CaseIterable, Codable, Sendable, Identifiable {
    case unspecified, female, male

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .unspecified: return "指定なし"
        case .female: return "女性"
        case .male: return "男性"
        }
    }
}

/// 年齢感。
public enum AgeFeel: String, CaseIterable, Codable, Sendable, Identifiable {
    case unspecified, child, teen, young, adult, senior

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .unspecified: return "指定なし"
        case .child: return "子ども"
        case .teen: return "10代"
        case .young: return "20代"
        case .adult: return "大人"
        case .senior: return "年配"
        }
    }

    /// キャプションに入れる人物の呼び方。性別と年齢感の両方が指定なしなら nil。
    public func personNoun(for gender: Gender) -> String? {
        switch (self, gender) {
        case (.unspecified, .unspecified): return nil
        case (.unspecified, .female): return "女性"
        case (.unspecified, .male): return "男性"
        case (.child, .female): return "女の子"
        case (.child, .male): return "男の子"
        case (.child, .unspecified): return "子ども"
        case (.teen, .female): return "少女"
        case (.teen, .male): return "少年"
        case (.teen, .unspecified): return "10代の若者"
        case (.young, .female): return "若い女性"
        case (.young, .male): return "青年"
        case (.young, .unspecified): return "若い人"
        case (.adult, .female): return "大人の女性"
        case (.adult, .male): return "大人の男性"
        case (.adult, .unspecified): return "大人"
        case (.senior, .female): return "年配の女性"
        case (.senior, .male): return "年配の男性"
        case (.senior, .unspecified): return "年配の人"
        }
    }
}

/// 声の高さ。雰囲気とは別に選ぶ（コーヘイ確認済み）。
public enum Pitch: String, CaseIterable, Codable, Sendable, Identifiable {
    case high, normal, low

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .high: return "高め"
        case .normal: return "普通"
        case .low: return "低め"
        }
    }
}

/// 雰囲気。複数選べる（コーヘイ確認済み）。並び順がそのまま画面とキャプションの順になる。
public enum Mood: String, CaseIterable, Codable, Sendable, Identifiable {
    case cute, gentle, cool, energetic, calm, teasing, sultry, languid, dignified, husky, breathy

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cute: return "可愛い"
        case .gentle: return "優しい"
        case .cool: return "クール"
        case .energetic: return "元気"
        case .calm: return "落ち着いた"
        case .teasing: return "いたずらっぽい"
        case .sultry: return "色っぽい"
        case .languid: return "けだるげ"
        case .dignified: return "凛とした"
        case .husky: return "ハスキー"
        case .breathy: return "吐息まじり"
        }
    }

    /// 「〜な声」の形（最後の1つに使う）
    var attributive: String {
        switch self {
        case .cute: return "可愛らしい"
        case .gentle: return "優しい"
        case .cool: return "クールな"
        case .energetic: return "元気で明るい"
        case .calm: return "落ち着いた"
        case .teasing: return "いたずらっぽい"
        case .sultry: return "色っぽい"
        case .languid: return "けだるげな"
        case .dignified: return "凛とした"
        case .husky: return "少しハスキーな"
        case .breathy: return "吐息まじりの"
        }
    }

    /// 次へつなぐ形（「優しくて」「クールで」）
    var connective: String {
        switch self {
        case .cute: return "可愛らしくて"
        case .gentle: return "優しくて"
        case .cool: return "クールで"
        case .energetic: return "元気で明るくて"
        case .calm: return "落ち着いていて"
        case .teasing: return "いたずらっぽくて"
        case .sultry: return "色っぽくて"
        case .languid: return "けだるげで"
        case .dignified: return "凛としていて"
        case .husky: return "少しハスキーで"
        case .breathy: return "吐息まじりで"
        }
    }

    /// 話し方。声質だけの雰囲気（ハスキーなど）は nil。
    var manner: String? {
        switch self {
        case .cute: return "甘えるように"
        case .gentle: return "柔らかく穏やかに"
        case .cool: return "感情を抑えて淡々と"
        case .energetic: return "ハキハキと"
        case .calm: return "ゆったりと"
        case .teasing: return "少しからかうように"
        case .sultry: return "艶っぽく"
        case .languid: return "気だるそうに"
        case .dignified: return "はっきりと"
        case .husky, .breathy: return nil
        }
    }
}

/// 声づくりの選択肢一式。ここからキャプションを組み立てる。
public struct VoiceSettings: Hashable, Codable, Sendable {
    public var gender: Gender
    public var age: AgeFeel
    public var moods: Set<Mood>
    public var pitch: Pitch
    public var seed: Int

    public init(
        gender: Gender = .female,
        age: AgeFeel = .teen,
        moods: Set<Mood> = [],
        pitch: Pitch = .normal,
        seed: Int = 1
    ) {
        self.gender = gender
        self.age = age
        self.moods = moods
        self.pitch = pitch
        self.seed = seed
    }

    /// seed として選べる範囲（全画面で共通）
    public static let seedRange = 0...99_999

    /// 画面に並べる順（Mood.allCases の順）に並べた雰囲気
    public var orderedMoods: [Mood] {
        Mood.allCases.filter(moods.contains)
    }
}
