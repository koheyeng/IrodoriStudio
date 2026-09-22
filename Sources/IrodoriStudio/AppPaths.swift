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
}
