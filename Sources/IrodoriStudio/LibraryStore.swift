import Foundation
import IrodoriKit

/// 見本・台本・完成音声一覧・声づくりの下書きを JSON で読み書きする。
enum LibraryStore {
    private static let currentVersion = 1

    /// 読み書きする中身一式
    struct Content {
        var references: [VoiceReference]
        var projects: [Project]
        var clips: [GeneratedClip]
        var design: VoiceDesignDraft
    }

    /// 声づくりの下書きの保存形（VoiceDesignDraft は Codable ではないのでここだけ写す）
    private struct DesignFile: Codable {
        var voice: VoiceProfile
        var text: String
        var status: LineStatus
        var lastClipID: GeneratedClip.ID?
    }

    private struct File: Codable {
        var version: Int
        var references: [VoiceReference]
        var projects: [Project]
        var clips: [GeneratedClip]
        var design: DesignFile
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `url` から読み込む。ファイルが無ければ nil（サンプルデータを使う合図）。
    /// 壊れていれば `<ファイル名>.bak` に退避してから nil を返す。
    static func load(from url: URL) -> Content? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data) else {
            backupCorrupted(at: url)
            return nil
        }
        return repair(file)
    }

    /// `url` に保存する
    static func save(_ content: Content, to url: URL) throws {
        let file = File(
            version: currentVersion,
            references: content.references,
            projects: content.projects,
            clips: content.clips,
            design: DesignFile(
                voice: content.design.voice,
                text: content.design.text,
                status: content.design.status,
                lastClipID: content.design.lastClipID
            )
        )
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func backupCorrupted(at url: URL) {
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
    }

    /// 前回終了時に中断していた状態を戻し、行方不明の音声ファイルを整理する
    private static func repair(_ file: File) -> Content {
        let clips = file.clips.filter { FileManager.default.fileExists(atPath: $0.audioURL.path) }
        let survivingClipIDs = Set(clips.map(\.id))

        var references = file.references
        for i in references.indices {
            if let audioURL = references[i].audioURL, !FileManager.default.fileExists(atPath: audioURL.path) {
                references[i].audioURL = nil
            }
        }

        var projects = file.projects
        for p in projects.indices {
            for l in projects[p].lines.indices {
                var line = projects[p].lines[l]
                repairStatusAndClip(status: &line.status, clipID: &line.clipID, survivingClipIDs: survivingClipIDs)
                projects[p].lines[l] = line
            }
        }

        var status = file.design.status
        var lastClipID = file.design.lastClipID
        repairStatusAndClip(status: &status, clipID: &lastClipID, survivingClipIDs: survivingClipIDs)
        var design = VoiceDesignDraft()
        design.voice = file.design.voice
        design.text = file.design.text
        design.status = status
        design.lastClipID = lastClipID

        return Content(references: references, projects: projects, clips: clips, design: design)
    }

    /// 待機中・生成中を未生成に戻し、消えた音声を指していたら外す
    private static func repairStatusAndClip(status: inout LineStatus, clipID: inout GeneratedClip.ID?, survivingClipIDs: Set<GeneratedClip.ID>) {
        if status.isBusy {
            status = .notGenerated
        }
        if let id = clipID, !survivingClipIDs.contains(id) {
            clipID = nil
            if status == .generated { status = .notGenerated }
        }
    }
}
