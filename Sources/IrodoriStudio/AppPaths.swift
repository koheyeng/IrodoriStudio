import Foundation

enum AppPaths {
    /// ダミー音声。.app ならバンドルの Resources/DummyAudio、`swift run` ならリポジトリの Resources/DummyAudio
    static var dummyAudio: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("DummyAudio"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // IrodoriStudio
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // リポジトリ
            .appendingPathComponent("Resources/DummyAudio")
    }

    /// 焼いた音声の置き場
    static var outputs: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IrodoriStudio/Outputs")
    }

    /// 設定画面のプレースホルダ用（表示だけ。実際の既定値は `engineRepo` 参照）
    static let defaultEngineRepoPath = "~/dev/github/Irodori-TTS"

    /// Irodori-TTS 本体のリポジトリ。設定画面の「エンジンのリポジトリ」欄（UserDefaults キー `engineRepoPath`）で上書きできる
    static var engineRepo: URL {
        if let override = UserDefaults.standard.string(forKey: "engineRepoPath")?.trimmingCharacters(in: .whitespaces),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/github/Irodori-TTS")
    }

    /// エンジンを動かす Python。既定はエンジンのリポジトリの `.venv/bin/python`。
    /// 設定画面の「エンジンの Python」欄（UserDefaults キー `enginePythonPath`）で直接指定もできる
    static var enginePython: URL {
        if let override = UserDefaults.standard.string(forKey: "enginePythonPath")?.trimmingCharacters(in: .whitespaces),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return engineRepo.appendingPathComponent(".venv/bin/python")
    }

    /// Python ワーカースクリプト（irodori_worker.py）。.app ならバンドルの Resources、`swift run` ならこのリポジトリの python/
    static var workerScript: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("irodori_worker.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // IrodoriStudio
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // リポジトリ
            .appendingPathComponent("python/irodori_worker.py")
    }
}
