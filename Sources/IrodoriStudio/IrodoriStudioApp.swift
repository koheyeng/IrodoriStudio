import AppKit
import IrodoriKit
import SwiftUI

@main
struct IrodoriStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.makeMock()
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup("Irodori Studio") {
            ContentView()
                .environment(model)
                .environment(player)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DevSnapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker("モデル", selection: Binding(get: { model.ttsModel }, set: { model.switchModel($0) })) {
                ForEach(TTSModel.allCases) { Text($0.label).tag($0) }
            }
            Text("切り替えるとモデルを読み込み直します（本物は約5〜40秒）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
