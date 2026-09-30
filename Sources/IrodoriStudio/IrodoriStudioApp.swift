import AppKit
import IrodoriKit
import SwiftUI

@main
struct IrodoriStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = Self.makeModel()
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup("Irodori Studio") {
            ContentView()
                .environment(model)
                .environment(player)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    appDelegate.model = model
                    model.selection = Self.launchScreen(model) ?? model.selection
                    await model.start()
                }
        }
        .defaultSize(width: 1240, height: 800)

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    /// `-mock` を付けて起動するとモック（デザイン確認・スクショ用）、それ以外は本物の Python ワーカーに繋ぐ
    private static func makeModel() -> AppModel {
        CommandLine.arguments.contains("-mock") ? .makeMock() : .makeLive()
    }

    /// 起動時に開く画面（スクショ確認用）。`open IrodoriStudio.app --args -screen project2` のように渡す（newProject は空の台本を作って開く）
    @MainActor
    private static func launchScreen(_ model: AppModel) -> SidebarItem? {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "voiceDesign": return .voiceDesign
        case "references": return .references
        case "clips": return .clips
        case "newProject": return .project(model.addProject().id)
        case let name? where name.hasPrefix("project"):
            let index = (Int(name.dropFirst("project".count)) ?? 1) - 1
            return model.projects.indices.contains(index) ? .project(model.projects[index].id) : nil
        default: return nil
        }
    }
}

/// `swift run` で素の実行ファイルとして起動しても、Dock に出て前面に来るようにする
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 終了時の保存フラッシュ用（IrodoriStudioApp の .task で渡される）
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DevSnapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushPendingSave()
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("engineRepoPath") private var engineRepoPath = ""
    @AppStorage("enginePythonPath") private var enginePythonPath = ""

    var body: some View {
        Form {
            Picker("モデル", selection: Binding(get: { model.ttsModel }, set: { model.switchModel($0) })) {
                ForEach(TTSModel.allCases) { Text($0.label).tag($0) }
            }
            Text("切り替えるとモデルを読み込み直します（Small・Anime版は約15秒、Large は約1分。Large は1本あたり再生時間の2倍ほどかかり、GPUメモリを約19GB使います）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("音声合成エンジンの場所") {
                TextField("リポジトリ", text: $engineRepoPath, prompt: Text(AppPaths.defaultEngineRepoPath))
                TextField("Python", text: $enginePythonPath, prompt: Text("既定: 上のリポジトリの .venv/bin/python"))
                Text("空欄なら既定の場所を使う。変更はアプリの再起動後に反映されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
