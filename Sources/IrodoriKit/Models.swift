import Foundation

/// 声の設定一式。声づくり画面・登場キャラで共通に使う。
public struct VoiceProfile: Hashable, Codable, Sendable {
    public var settings: VoiceSettings
    /// 実際に渡すキャプション。設定から自動で組み立てるが、手で書き換えてもよい。
    public var caption: String
    /// 手で書き換えたら true。true の間は設定を変えてもキャプションを上書きしない。
    public var isCaptionEdited: Bool
    /// 読み込んだ声の見本（nil なら見本を使っていない）
    public var referenceID: VoiceReference.ID?
    /// 見本の音声を参照音声にして声を固定する。固定中はキャプションを話し方だけにする（声質は参照音声に任せる）
    public var isReferenceFixed: Bool

    /// 参照音声として使う見本（固定していなければ nil）
    public var fixedReferenceID: VoiceReference.ID? { isReferenceFixed ? referenceID : nil }

    public init(
        settings: VoiceSettings = VoiceSettings(),
        caption: String? = nil,
        referenceID: VoiceReference.ID? = nil,
        isReferenceFixed: Bool = false
    ) {
        self.settings = settings
        self.referenceID = referenceID
        self.isReferenceFixed = isReferenceFixed && referenceID != nil
        let built = CaptionBuilder.build(from: settings, includeVoiceQuality: !self.isReferenceFixed)
        self.caption = caption ?? built
        self.isCaptionEdited = caption != nil && caption != built
    }

    /// 見本を読み込む。設定（seed 含む）とキャプションが入る。固定の on/off はそのまま引き継ぐ。
    public mutating func load(_ reference: VoiceReference) {
        settings = reference.settings
        referenceID = reference.id
        if isReferenceFixed {
            resetCaptionToAuto()
        } else {
            caption = reference.caption
            isCaptionEdited = reference.caption != CaptionBuilder.build(from: settings)
        }
    }

    /// 「この声で固定」の切り替え。見本を読み込んでいないときは固定できない。
    public mutating func setReferenceFixed(_ fixed: Bool) {
        isReferenceFixed = fixed && referenceID != nil
        refreshCaptionIfAuto()
    }

    /// 見本が消されたときに呼ぶ。その見本を読み込んでいたら外し、固定も解く。
    public mutating func detachReference(_ id: VoiceReference.ID) {
        guard referenceID == id else { return }
        referenceID = nil
        isReferenceFixed = false
        refreshCaptionIfAuto()
    }

    /// 手で書き換えていなければ、今の設定からキャプションを作り直す。
    public mutating func refreshCaptionIfAuto() {
        guard !isCaptionEdited else { return }
        caption = CaptionBuilder.build(from: settings, includeVoiceQuality: !isReferenceFixed)
    }

    /// 手書きをやめて、設定から作り直す。
    public mutating func resetCaptionToAuto() {
        isCaptionEdited = false
        refreshCaptionIfAuto()
    }
}

/// 声の見本（リファレンス）。
/// 選ぶと設定（キャプション＋seed）が入る。「この声で固定」にすると音声が参照音声になり、台本の全セリフを同じ声で焼ける。
public struct VoiceReference: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var settings: VoiceSettings
    public var caption: String
    /// 見本として焼いたセリフ
    public var sampleText: String
    /// 見本の音声（参照音声としても使う）
    public var audioURL: URL?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        settings: VoiceSettings,
        caption: String,
        sampleText: String,
        audioURL: URL?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.caption = caption
        self.sampleText = sampleText
        self.audioURL = audioURL
        self.createdAt = createdAt
    }
}

/// 台本の登場キャラ。各セリフ行はキャラを選ぶだけで声が決まる。
public struct CastMember: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// 行の見分け用の色番号（画面側でパレットに当てる）
    public var colorIndex: Int
    public var voice: VoiceProfile

    public init(id: UUID = UUID(), name: String, colorIndex: Int, voice: VoiceProfile) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.voice = voice
    }
}

/// セリフ行の状態
public enum LineStatus: Hashable, Codable, Sendable {
    case notGenerated
    /// 順番待ち（MPS は同時に1本しか焼けないので、キューに並ぶ）
    case queued
    case generating(progress: Double)
    case generated
    case failed(message: String)

    public var label: String {
        switch self {
        case .notGenerated: return "未生成"
        case .queued: return "待機中"
        case .generating: return "生成中"
        case .generated: return "生成済み"
        case .failed: return "失敗"
        }
    }

    public var isBusy: Bool {
        switch self {
        case .queued, .generating: return true
        default: return false
        }
    }
}

/// 台本の1行。
public struct ScriptLine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var characterID: CastMember.ID?
    public var text: String
    /// この行だけキャプションを変えたいとき（nil ならキャラのキャプション）
    public var captionOverride: String?
    /// この行だけ seed を変えたいとき（nil ならキャラの seed）
    public var seedOverride: Int?
    public var status: LineStatus
    /// 焼いた音声（完成音声一覧の GeneratedClip）
    public var clipID: GeneratedClip.ID?

    public init(
        id: UUID = UUID(),
        characterID: CastMember.ID?,
        text: String,
        captionOverride: String? = nil,
        seedOverride: Int? = nil,
        status: LineStatus = .notGenerated,
        clipID: GeneratedClip.ID? = nil
    ) {
        self.id = id
        self.characterID = characterID
        self.text = text
        self.captionOverride = captionOverride
        self.seedOverride = seedOverride
        self.status = status
        self.clipID = clipID
    }
}

/// 台本プロジェクト。複数持てる。
public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var characters: [CastMember]
    public var lines: [ScriptLine]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        characters: [CastMember] = [],
        lines: [ScriptLine] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.characters = characters
        self.lines = lines
        self.updatedAt = updatedAt
    }

    public func character(_ id: CastMember.ID?) -> CastMember? {
        guard let id else { return nil }
        return characters.first { $0.id == id }
    }
}

/// 完成音声（焼き上がった1本）
public struct GeneratedClip: Identifiable, Hashable, Codable, Sendable {
    public enum Source: Hashable, Codable, Sendable {
        case voiceDesign
        case project(id: Project.ID, name: String)
    }

    public let id: UUID
    public var text: String
    public var caption: String?
    public var seed: Int
    /// 声を固定した見本の名前（固定していなければ nil）
    public var referenceName: String?
    /// キャラの名前（台本から焼いたとき）
    public var characterName: String?
    public var audioURL: URL
    public var duration: TimeInterval
    public var createdAt: Date
    public var source: Source

    public init(
        id: UUID = UUID(),
        text: String,
        caption: String?,
        seed: Int,
        referenceName: String? = nil,
        characterName: String? = nil,
        audioURL: URL,
        duration: TimeInterval,
        createdAt: Date = .now,
        source: Source
    ) {
        self.id = id
        self.text = text
        self.caption = caption
        self.seed = seed
        self.referenceName = referenceName
        self.characterName = characterName
        self.audioURL = audioURL
        self.duration = duration
        self.createdAt = createdAt
        self.source = source
    }
}
