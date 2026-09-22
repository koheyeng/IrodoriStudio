import AppKit

/// デザイン確認用: `-snapshot 出力.png` を渡して起動すると、少し待ってからメインウィンドウを PNG に書き出す。
/// `-snapshotDelay 秒` で待ち時間を変えられる。
enum DevSnapshot {
    @MainActor
    static func scheduleIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "snapshot") else { return }
        let delay = UserDefaults.standard.double(forKey: "snapshotDelay")
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay > 0 ? delay : 3)) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.resizable) }),
                  let frameView = window.contentView?.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
