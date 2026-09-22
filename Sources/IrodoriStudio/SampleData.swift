import Foundation
import IrodoriKit

/// モック用のダミーデータ。前のセッションで実際に焼いた声（採用ボイス・聴き比べ40本）から作った。
enum SampleData {
    struct Content {
        var references: [VoiceReference]
        var projects: [Project]
        var clips: [GeneratedClip]
    }

    static func make(dummyAudio: URL) -> Content {
        func audio(_ name: String) -> URL { dummyAudio.appendingPathComponent("\(name).wav") }
        let now = Date.now
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // MARK: 声の見本
        let husky = VoiceReference(
            name: "ハスキー美少女（採用1）",
            settings: VoiceSettings(gender: .female, age: .teen, moods: [.calm, .teasing, .husky], seed: 1),
            caption: "少しハスキーな落ち着いた声の美少女。優しい眼差しで微笑みながら、少しからかうように柔らかく話す。",
            sampleText: "ねえ……さっきからずっと、こっち見てたでしょ？😏",
            audioURL: audio("adopt1_husky"), createdAt: ago(60 * 26)
        )
        let breathy = VoiceReference(
            name: "吐息まじり（採用2）",
            settings: VoiceSettings(gender: .female, age: .young, moods: [.gentle, .teasing, .breathy], seed: 1),
            caption: "吐息まじりの少しハスキーな声。穏やかで優しい雰囲気で、くすっと笑いながら軽くからかうように話す。",
            sampleText: "🫶ねえ……さっきからずっと、こっち見てたでしょ？🤭",
            audioURL: audio("adopt2_breathy"), createdAt: ago(60 * 25)
        )
        let genki = VoiceReference(
            name: "元気少女",
            settings: VoiceSettings(gender: .female, age: .teen, moods: [.energetic], pitch: .high, seed: 1),
            caption: "元気で明るいアニメ風の少女。ハキハキとした話し方。",
            sampleText: "おはよー！今日の放課後、駅前にできた新しいクレープ屋さん、一緒に行こうよ！",
            audioURL: audio("c02_genki"), createdAt: ago(60 * 24)
        )
        let teasing = VoiceReference(
            name: "からかい",
            settings: VoiceSettings(gender: .female, age: .teen, moods: [.teasing], seed: 1),
            caption: "からかうような、いたずらっぽい口調で話す少女の声。",
            sampleText: "ふふっ🤭、顔真っ赤だよ？もしかして、照れてるの？😏",
            audioURL: audio("c03_karakai"), createdAt: ago(60 * 24)
        )
        let whisper = VoiceReference(
            name: "囁き",
            settings: VoiceSettings(gender: .female, age: .young, moods: [.sultry, .gentle], seed: 1),
            caption: "耳元で囁くような、甘くて距離の近い若い女性の声。",
            sampleText: "👂ねえ、みんなには内緒だよ……😮‍💨今夜、こっそり会いに行くから。",
            audioURL: audio("c04_sasayaki"), createdAt: ago(60 * 23)
        )
        let crying = VoiceReference(
            name: "泣き",
            settings: VoiceSettings(gender: .female, age: .teen, moods: [.gentle], seed: 1),
            caption: "深く傷つき、泣きながら震える声で話す少女。",
            sampleText: "どうして……どうして置いていったの😭ずっと、ずっと待ってたのに。",
            audioURL: audio("c05_naki"), createdAt: ago(60 * 23)
        )
        let cool = VoiceReference(
            name: "クール",
            settings: VoiceSettings(gender: .female, age: .young, moods: [.cool, .calm], pitch: .low, seed: 1),
            caption: "落ち着いた低めの女性の声。感情を抑えたクールな話し方。",
            sampleText: "……別に。あなたのために淹れたわけじゃないから。冷めないうちに飲んで。",
            audioURL: audio("c06_cool"), createdAt: ago(60 * 22)
        )
        let angry = VoiceReference(
            name: "怒り",
            settings: VoiceSettings(gender: .female, age: .teen, moods: [.energetic], pitch: .high, seed: 1),
            caption: "怒って声を荒げる少女。勢いよく早口で。",
            sampleText: "ちょっと！何回言ったらわかるの😠！もう知らないんだから！",
            audioURL: audio("c07_ikari"), createdAt: ago(60 * 22)
        )
        let youngMan = VoiceReference(
            name: "落ち着いた青年",
            settings: VoiceSettings(gender: .male, age: .young, moods: [.calm, .gentle], pitch: .low, seed: 1),
            caption: "落ち着いた低い声の青年。優しく包み込むように話す。",
            sampleText: "大丈夫。俺がついてる。だから、もう泣くな。",
            audioURL: audio("c08_dansei"), createdAt: ago(60 * 21)
        )
        let mama = VoiceReference(
            name: "甘やかしママ",
            settings: VoiceSettings(gender: .female, age: .adult, moods: [.gentle, .calm], seed: 1),
            caption: "おっとりとした優しい大人の女性の声。甘やかすように、ゆっくり話す。",
            sampleText: "おかえりなさい。今日も一日よく頑張ったね。ほら、こっちにおいで🫶",
            audioURL: audio("c09_mama"), createdAt: ago(60 * 21)
        )
        let references = [husky, breathy, genki, teasing, whisper, crying, cool, angry, youngMan, mama]

        // MARK: 完成音声（生成済みの行と、声づくりで焼いたもの）
        func clip(_ text: String, _ caption: String?, _ file: String, character: String? = nil,
                  reference: String? = nil, source: GeneratedClip.Source, at date: Date) -> GeneratedClip {
            let url = audio(file)
            return GeneratedClip(
                text: text, caption: caption, seed: 1, referenceName: reference, characterName: character,
                audioURL: url, duration: MockSpeechSynthesizer.duration(of: url), createdAt: date, source: source
            )
        }

        // MARK: 台本1 放課後の告白
        let mashiro = CastMember(name: "真白", colorIndex: 0,
                                voice: VoiceProfile(settings: husky.settings, referenceID: husky.id, isReferenceFixed: true))
        let hinata = CastMember(name: "ひなた", colorIndex: 1,
                               voice: VoiceProfile(settings: genki.settings, caption: genki.caption))
        let yu = CastMember(name: "ユウ", colorIndex: 2,
                           voice: VoiceProfile(settings: youngMan.settings, caption: youngMan.caption))
        let galgeID = UUID()
        let galgeSource = GeneratedClip.Source.project(id: galgeID, name: "放課後の告白")

        let line1Clip = clip("ねえ……さっきからずっと、こっち見てたでしょ？😏", mashiro.voice.caption, "adopt1_husky",
                             character: mashiro.name, reference: husky.name, source: galgeSource, at: ago(40))
        let line2Clip = clip("え、いや、見てないって。", yu.voice.caption, "c08_dansei",
                             character: yu.name, source: galgeSource, at: ago(39))
        let line3Clip = clip("🫶ふーん……😮‍💨じゃあ、今こっち見てるのは誰かな？🤭", mashiro.voice.caption, "adopt2_breathy",
                             character: mashiro.name, reference: husky.name, source: galgeSource, at: ago(38))

        let galge = Project(
            id: galgeID,
            name: "放課後の告白",
            characters: [mashiro, hinata, yu],
            lines: [
                ScriptLine(characterID: mashiro.id, text: line1Clip.text, status: .generated, clipID: line1Clip.id),
                ScriptLine(characterID: yu.id, text: line2Clip.text, status: .generated, clipID: line2Clip.id),
                ScriptLine(characterID: mashiro.id, text: line3Clip.text, status: .generated, clipID: line3Clip.id),
                ScriptLine(characterID: hinata.id, text: "あー！二人ともここにいたー！💥探したんだよ？"),
                ScriptLine(characterID: yu.id, text: "ひなた、声でかいって……🙄"),
                ScriptLine(characterID: mashiro.id,
                           text: "⏸️……また、放課後にね。今日はちゃんと、最後まで聞いてもらうから。逃げたら許さないよ？ずっと待ってたんだから。ずっと、ずっと前から。😏",
                           status: .failed(message: "1回の生成は30秒までです。句点で2つに分けてください")),
                ScriptLine(characterID: hinata.id, text: "え、なになに？何の話？😲", seedOverride: 2),
            ],
            updatedAt: ago(38)
        )

        // MARK: 台本2 朗読テスト
        let narrator = CastMember(name: "ナレーター", colorIndex: 3,
                                 voice: VoiceProfile(settings: VoiceSettings(gender: .female, age: .adult, moods: [.calm], seed: 3)))
        let reading = Project(
            name: "朗読テスト",
            characters: [narrator],
            lines: [
                ScriptLine(characterID: narrator.id, text: "📖本日は晴天なり。昨日の会議で決まった予算案について、改めて確認させていただきます。"),
                ScriptLine(characterID: narrator.id, text: "📖昔々、ある山のふもとに、小さな村がありました。"),
                ScriptLine(characterID: narrator.id, text: "🐢村の人たちは、毎朝早くから畑に出て働いていました。"),
            ],
            updatedAt: ago(60 * 5)
        )

        // MARK: 台本3 ASMR
        let whisperer = CastMember(name: "お姉さん", colorIndex: 4,
                                  voice: VoiceProfile(settings: whisper.settings, caption: whisper.caption))
        let asmr = Project(
            name: "ASMR 耳かき",
            characters: [whisperer],
            lines: [
                ScriptLine(characterID: whisperer.id, text: "👂じっとしててね……😮‍💨痛くない？"),
                ScriptLine(characterID: whisperer.id, text: "👂ふふ、気持ちよさそうな顔🤭"),
            ],
            updatedAt: ago(60 * 30)
        )

        let designClips = [
            clip("ふふっ🤭、顔真っ赤だよ？もしかして、照れてるの？😏", teasing.caption, "c03_karakai", source: .voiceDesign, at: ago(90)),
            clip("……別に。あなたのために淹れたわけじゃないから。冷めないうちに飲んで。", cool.caption, "c06_cool", source: .voiceDesign, at: ago(95)),
            clip("はぁ……はぁ……🌬️もう、走れない……ちょっとだけ、休ませて……🥵", "息を切らした少女。", "c10_ikigire", source: .voiceDesign, at: ago(100)),
        ]

        return Content(
            references: references,
            projects: [galge, reading, asmr],
            clips: [line3Clip, line2Clip, line1Clip] + designClips
        )
    }
}
