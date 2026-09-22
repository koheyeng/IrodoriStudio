import Foundation
import Testing
import IrodoriKit
@testable import IrodoriStudio

@Suite struct LibraryStoreTests {
    /// 一時ディレクトリを用意する（本物の Application Support は絶対に触らない）
    static func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func touch(_ url: URL) {
        try! Data().write(to: url)
    }

    @Test func roundTripPreservesData() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let libraryURL = dir.appendingPathComponent("library.json")

        let clipAudio = dir.appendingPathComponent("clip1.wav")
        Self.touch(clipAudio)
        let refAudio = dir.appendingPathComponent("ref1.wav")
        Self.touch(refAudio)

        // ISO8601 は秒未満を保持しないので、比較用に秒単位の日時を使う
        let wholeSecond = Date(timeIntervalSince1970: 1_700_000_000)
        let reference = VoiceReference(name: "見本", settings: VoiceSettings(), caption: "キャプション", sampleText: "サンプル", audioURL: refAudio, createdAt: wholeSecond)
        let clip = GeneratedClip(text: "セリフ", caption: "キャプション", seed: 1, audioURL: clipAudio, duration: 1.2, createdAt: wholeSecond, source: .voiceDesign)
        let line = ScriptLine(characterID: nil, text: "行", status: .generated, clipID: clip.id)
        let project = Project(name: "台本", characters: [], lines: [line])
        var design = VoiceDesignDraft()
        design.text = "下書き"
        design.lastClipID = clip.id

        let content = LibraryStore.Content(references: [reference], projects: [project], clips: [clip], design: design)
        try LibraryStore.save(content, to: libraryURL)

        let loaded = try #require(LibraryStore.load(from: libraryURL))
        #expect(loaded.references == [reference])
        #expect(loaded.clips == [clip])
        #expect(loaded.projects.first?.lines.first?.status == .generated)
        #expect(loaded.projects.first?.lines.first?.clipID == clip.id)
        #expect(loaded.design.text == "下書き")
        #expect(loaded.design.lastClipID == clip.id)
    }

    @Test func busyStatusesResetOnLoad() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let libraryURL = dir.appendingPathComponent("library.json")

        let queuedLine = ScriptLine(characterID: nil, text: "待機中の行", status: .queued)
        let generatingLine = ScriptLine(characterID: nil, text: "生成中の行", status: .generating(progress: 0.5))
        let project = Project(name: "台本", characters: [], lines: [queuedLine, generatingLine])
        var design = VoiceDesignDraft()
        design.status = .queued

        let content = LibraryStore.Content(references: [], projects: [project], clips: [], design: design)
        try LibraryStore.save(content, to: libraryURL)

        let loaded = try #require(LibraryStore.load(from: libraryURL))
        #expect(loaded.projects.first?.lines[0].status == .notGenerated)
        #expect(loaded.projects.first?.lines[1].status == .notGenerated)
        #expect(loaded.design.status == .notGenerated)
    }

    @Test func missingClipAudioDropsClipAndClearsLine() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let libraryURL = dir.appendingPathComponent("library.json")

        let missingAudio = dir.appendingPathComponent("missing.wav") // 作らない = ファイルが無い状態
        let clip = GeneratedClip(text: "セリフ", caption: nil, seed: 1, audioURL: missingAudio, duration: 1.0, source: .voiceDesign)
        let line = ScriptLine(characterID: nil, text: "行", status: .generated, clipID: clip.id)
        let project = Project(name: "台本", characters: [], lines: [line])

        let content = LibraryStore.Content(references: [], projects: [project], clips: [clip], design: VoiceDesignDraft())
        try LibraryStore.save(content, to: libraryURL)

        let loaded = try #require(LibraryStore.load(from: libraryURL))
        #expect(loaded.clips.isEmpty)
        #expect(loaded.projects.first?.lines.first?.clipID == nil)
        #expect(loaded.projects.first?.lines.first?.status == .notGenerated)
    }

    @Test func missingReferenceAudioSurvivesWithNilURL() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let libraryURL = dir.appendingPathComponent("library.json")

        let missingAudio = dir.appendingPathComponent("missing.wav") // 作らない = ファイルが無い状態
        let reference = VoiceReference(name: "見本", settings: VoiceSettings(), caption: "", sampleText: "", audioURL: missingAudio)

        let content = LibraryStore.Content(references: [reference], projects: [], clips: [], design: VoiceDesignDraft())
        try LibraryStore.save(content, to: libraryURL)

        let loaded = try #require(LibraryStore.load(from: libraryURL))
        #expect(loaded.references.count == 1)
        #expect(loaded.references.first?.audioURL == nil)
        #expect(loaded.references.first?.id == reference.id)
    }

    @Test func corruptJSONBacksUpAndSignalsSeed() throws {
        let dir = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let libraryURL = dir.appendingPathComponent("library.json")
        try "not valid json".write(to: libraryURL, atomically: true, encoding: .utf8)

        let loaded = LibraryStore.load(from: libraryURL)
        #expect(loaded == nil)

        let backupURL = dir.appendingPathComponent("library.json.bak")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: libraryURL.path))
    }
}
