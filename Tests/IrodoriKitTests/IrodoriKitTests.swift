import Foundation
import Testing
@testable import IrodoriKit

@Suite struct CaptionBuilderTests {
    @Test func buildsQualityAndManner() {
        let settings = VoiceSettings(gender: .female, age: .teen, moods: [.gentle, .teasing], pitch: .high)
        #expect(CaptionBuilder.build(from: settings)
            == "高めで優しくていたずらっぽい声の少女。柔らかく穏やかに、少しからかうように話す。")
    }

    @Test func pitchOnly() {
        let settings = VoiceSettings(gender: .male, age: .young, moods: [], pitch: .low)
        #expect(CaptionBuilder.build(from: settings) == "低めの声の青年。")
    }

    @Test func nounOnly() {
        let settings = VoiceSettings(gender: .female, age: .adult, moods: [], pitch: .normal)
        #expect(CaptionBuilder.build(from: settings) == "大人の女性の声。")
    }

    @Test func nothingSelectedIsEmpty() {
        let settings = VoiceSettings(gender: .unspecified, age: .unspecified, moods: [], pitch: .normal)
        #expect(CaptionBuilder.build(from: settings) == "")
    }

    @Test func qualityOnlyMoodHasNoMannerSentence() {
        let settings = VoiceSettings(gender: .unspecified, age: .unspecified, moods: [.husky], pitch: .normal)
        #expect(CaptionBuilder.build(from: settings) == "少しハスキーな声。")
    }

    @Test func fixedReferenceLeavesOnlyManner() {
        let settings = VoiceSettings(gender: .female, age: .teen, moods: [.husky, .teasing], pitch: .normal)
        #expect(CaptionBuilder.build(from: settings, includeVoiceQuality: false) == "少しからかうように話す。")
    }
}

@Suite struct VoiceProfileTests {
    @Test func autoCaptionFollowsSettings() {
        var spec = VoiceProfile(settings: VoiceSettings(gender: .female, age: .teen))
        #expect(spec.caption == "少女の声。")
        spec.settings.moods = [.cool]
        spec.refreshCaptionIfAuto()
        #expect(spec.caption == "クールな声の少女。感情を抑えて淡々と話す。")
    }

    @Test func editedCaptionIsKeptUntilReset() {
        var spec = VoiceProfile(settings: VoiceSettings(), caption: "手書きのキャプション。")
        #expect(spec.isCaptionEdited)
        spec.settings.moods = [.cool]
        spec.refreshCaptionIfAuto()
        #expect(spec.caption == "手書きのキャプション。")
        spec.resetCaptionToAuto()
        #expect(spec.caption == "クールな声の少女。感情を抑えて淡々と話す。")
    }

    @Test func loadingReferenceBringsItsCaptionAndSeed() {
        let reference = VoiceReference(
            name: "見本", settings: VoiceSettings(moods: [.husky], seed: 7),
            caption: "少しハスキーな落ち着いた声の美少女。", sampleText: "", audioURL: nil
        )
        var spec = VoiceProfile()
        spec.load(reference)
        #expect(spec.caption == reference.caption)
        #expect(spec.settings.seed == 7)
        #expect(spec.fixedReferenceID == nil)
    }

    @Test func fixingReferenceDropsVoiceQualityFromCaption() {
        let reference = VoiceReference(
            name: "見本", settings: VoiceSettings(moods: [.husky, .teasing]),
            caption: "手書き。", sampleText: "", audioURL: nil
        )
        var spec = VoiceProfile()
        spec.setReferenceFixed(true)
        #expect(!spec.isReferenceFixed) // 見本を読み込むまでは固定できない
        spec.load(reference)
        spec.setReferenceFixed(true)
        spec.resetCaptionToAuto()
        #expect(spec.fixedReferenceID == reference.id)
        #expect(spec.caption == "少しからかうように話す。")
    }
}

@Suite struct DetachReferenceTests {
    @Test func detachingFixedReferenceRestoresVoiceQuality() {
        let reference = VoiceReference(
            name: "見本", settings: VoiceSettings(moods: [.husky, .teasing]),
            caption: "手書き。", sampleText: "", audioURL: nil
        )
        var spec = VoiceProfile()
        spec.load(reference)
        spec.setReferenceFixed(true)
        spec.resetCaptionToAuto()
        spec.detachReference(UUID()) // 別の見本なら何もしない
        #expect(spec.fixedReferenceID == reference.id)
        spec.detachReference(reference.id)
        #expect(spec.referenceID == nil)
        #expect(!spec.isReferenceFixed)
        #expect(spec.caption == "いたずらっぽくて少しハスキーな声の少女。少しからかうように話す。")
    }
}

@Suite struct EmojiPaletteTests {
    @Test func hasAllOfficialEmojiOnce() {
        #expect(EmojiPalette.items.count == 45)
        #expect(Set(EmojiPalette.items.map(\.emoji)).count == 45)
    }

    @Test func everyCategoryIsUsed() {
        for category in EmojiCategory.allCases {
            #expect(!EmojiPalette.items(in: category).isEmpty)
        }
    }
}

@Suite struct MockSynthesizerTests {
    static let dummyDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/DummyAudio")

    @Test func picksDummyByKeyword() throws {
        let mock = MockSpeechSynthesizer(dummyAudioDirectory: Self.dummyDirectory, outputDirectory: FileManager.default.temporaryDirectory)
        let request = SynthesisRequest(text: "もう知らない😠", caption: nil, seed: 1)
        #expect(try mock.pickDummy(for: request).lastPathComponent == "c07_ikari.wav")
    }

    @Test func synthesizeCopiesAudio() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrodoriKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        let mock = MockSpeechSynthesizer(dummyAudioDirectory: Self.dummyDirectory, outputDirectory: output)
        let result = try await mock.synthesize(SynthesisRequest(text: "テスト", caption: nil, seed: 0)) { _ in }
        #expect(FileManager.default.fileExists(atPath: result.audioURL.path))
        #expect(result.duration > 1)
    }
}
