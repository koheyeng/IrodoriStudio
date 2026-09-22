import Foundation

/// 絵文字の演技指導。飾りではなく「音を入れる制御記号」で、同じ絵文字を重ねるほど効果が強く・長くなる。
public struct EmojiItem: Hashable, Sendable, Identifiable {
    public let emoji: String
    public let name: String
    public let detail: String
    public let category: EmojiCategory

    public var id: String { emoji }

    /// ホバーで出す説明
    public var tooltip: String { "\(name): \(detail)" }
}

/// 公式パレットには分類が無いので、こちらで決めたグループ分け。
public enum EmojiCategory: String, CaseIterable, Sendable, Identifiable {
    case breath, voice, mouth, emotion, delivery, acoustic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breath: return "息・声の音"
        case .voice: return "笑い・泣き"
        case .mouth: return "口の音"
        case .emotion: return "感情・態度"
        case .delivery: return "話し方・テンポ"
        case .acoustic: return "音響"
        }
    }
}

public enum EmojiPalette {
    /// 公式45種（irodori_tts/gradio_emoji_palette.py の EMOJI_PALETTE_ITEMS と同じ並び・同じ文字）
    public static let items: [EmojiItem] = [
        EmojiItem(emoji: "👂", name: "囁き", detail: "耳元の音", category: .breath),
        EmojiItem(emoji: "😮‍💨", name: "吐息", detail: "溜息、寝息", category: .breath),
        EmojiItem(emoji: "⏸️", name: "間", detail: "沈黙", category: .delivery),
        EmojiItem(emoji: "🤭", name: "笑い", detail: "くすくす、含み笑い", category: .voice),
        EmojiItem(emoji: "🥵", name: "喘ぎ", detail: "うめき声、唸り声", category: .breath),
        EmojiItem(emoji: "📢", name: "エコー", detail: "リバーブ", category: .acoustic),
        EmojiItem(emoji: "😏", name: "からかう", detail: "甘えるように", category: .emotion),
        EmojiItem(emoji: "🥺", name: "震え声", detail: "自信なさげに", category: .emotion),
        EmojiItem(emoji: "🌬️", name: "息切れ", detail: "荒い息遣い、呼吸音", category: .breath),
        EmojiItem(emoji: "😮", name: "息をのむ", detail: "Gasp", category: .breath),
        EmojiItem(emoji: "👅", name: "舐める音", detail: "咀嚼音、水音", category: .mouth),
        EmojiItem(emoji: "💋", name: "リップノイズ", detail: "Lip smack", category: .mouth),
        EmojiItem(emoji: "🫶", name: "優しく", detail: "Tenderly", category: .emotion),
        EmojiItem(emoji: "😭", name: "泣き声", detail: "嗚咽、悲しみ", category: .voice),
        EmojiItem(emoji: "😱", name: "悲鳴", detail: "叫び、絶叫", category: .voice),
        EmojiItem(emoji: "😪", name: "眠そう", detail: "気だるげに", category: .emotion),
        EmojiItem(emoji: "😴", name: "寝言", detail: "いびき", category: .breath),
        EmojiItem(emoji: "⏩", name: "早口", detail: "一気に、急いで", category: .delivery),
        EmojiItem(emoji: "📞", name: "電話越し", detail: "スピーカー越し", category: .acoustic),
        EmojiItem(emoji: "🐢", name: "ゆっくり", detail: "Slowly", category: .delivery),
        EmojiItem(emoji: "🥤", name: "飲み込む", detail: "唾を飲む音", category: .breath),
        EmojiItem(emoji: "🤧", name: "咳・鼻", detail: "咳き込み、鼻すすり", category: .breath),
        EmojiItem(emoji: "😒", name: "舌打ち", detail: "Tutting", category: .mouth),
        EmojiItem(emoji: "😰", name: "慌てる", detail: "動揺、緊張、どもり", category: .emotion),
        EmojiItem(emoji: "😆", name: "喜び", detail: "嬉しそうに", category: .emotion),
        EmojiItem(emoji: "💥", name: "勢いよく", detail: "力強い勢い", category: .delivery),
        EmojiItem(emoji: "😠", name: "怒り", detail: "不満げ、拗ねる", category: .emotion),
        EmojiItem(emoji: "😲", name: "驚き", detail: "感嘆", category: .emotion),
        EmojiItem(emoji: "🥱", name: "あくび", detail: "Yawn", category: .breath),
        EmojiItem(emoji: "😖", name: "苦しげ", detail: "Agonizingly", category: .emotion),
        EmojiItem(emoji: "😟", name: "心配", detail: "不安そうに", category: .emotion),
        EmojiItem(emoji: "🫣", name: "照れ", detail: "恥ずかしそうに", category: .emotion),
        EmojiItem(emoji: "🙄", name: "呆れ", detail: "Exasperatedly", category: .emotion),
        EmojiItem(emoji: "😊", name: "楽しげ", detail: "嬉しそうに", category: .emotion),
        EmojiItem(emoji: "😎", name: "得意げ", detail: "自信ありげに", category: .emotion),
        EmojiItem(emoji: "👌", name: "相槌", detail: "頷く音", category: .voice),
        EmojiItem(emoji: "🙏", name: "懇願", detail: "お願いするように", category: .emotion),
        EmojiItem(emoji: "🥴", name: "酔う", detail: "Drunkenly", category: .emotion),
        EmojiItem(emoji: "🎵", name: "鼻歌", detail: "Humming", category: .voice),
        EmojiItem(emoji: "🤐", name: "口を塞ぐ", detail: "Muffled", category: .mouth),
        EmojiItem(emoji: "😌", name: "安堵", detail: "満足げに", category: .emotion),
        EmojiItem(emoji: "🤔", name: "疑問", detail: "Questioning", category: .emotion),
        EmojiItem(emoji: "💪", name: "力強く", detail: "力を込めて", category: .delivery),
        EmojiItem(emoji: "👃", name: "嗅ぐ音", detail: "匂いを嗅ぐ音", category: .mouth),
        EmojiItem(emoji: "📖", name: "朗読", detail: "ナレーション", category: .delivery),
    ]

    public static func items(in category: EmojiCategory) -> [EmojiItem] {
        items.filter { $0.category == category }
    }
}
