import IrodoriKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(selection: $model.selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            switch model.selection ?? .voiceDesign {
            case .voiceDesign:
                VoiceDesignView()
            case .references:
                ReferenceLibraryView()
            case .project(let id):
                if model.projectIndex(id) != nil {
                    ScriptView(projectID: id)
                        .id(id)
                } else {
                    ContentUnavailableView("台本が見つかりません", systemImage: "doc.questionmark")
                }
            case .clips:
                ClipLibraryView()
            }
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(AppModel.self) private var model
    @State private var renamingProjectID: Project.ID?

    var body: some View {
        @Bindable var model = model
        List(selection: $selection) {
            Section("つくる") {
                Label("声づくり", systemImage: "waveform.and.person.filled")
                    .tag(SidebarItem.voiceDesign)
                Label("声の見本", systemImage: "square.stack.3d.up")
                    .badge(model.references.count)
                    .tag(SidebarItem.references)
            }
            Section("台本") {
                ForEach($model.projects) { $project in
                    Group {
                        if renamingProjectID == project.id {
                            TextField("台本の名前", text: $project.name)
                                .onSubmit { renamingProjectID = nil }
                        } else {
                            Label(project.name, systemImage: "doc.text")
                                .badge(project.lines.count)
                        }
                    }
                    .tag(SidebarItem.project(project.id))
                    .contextMenu {
                        Button("名前を変更") { renamingProjectID = project.id }
                        Divider()
                        Button("削除", role: .destructive) { model.deleteProject(project.id) }
                    }
                }
                Button {
                    let project = model.addProject()
                    renamingProjectID = project.id
                } label: {
                    Label("新しい台本", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Section("書き出し") {
                Label("完成音声", systemImage: "music.note.list")
                    .badge(model.clips.count)
                    .tag(SidebarItem.clips)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            EngineStatusView()
                .padding(10)
        }
    }
}

/// サイドバーの一番下に出す、エンジン（モデル）の状態
private struct EngineStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            switch model.engineState {
            case .loading(let ttsModel):
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("モデルを読み込み中…")
                    Text(ttsModel.label).foregroundStyle(.secondary)
                }
            case .ready:
                Circle()
                    .fill(model.isGenerating ? Color.accentColor : Color.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isGenerating ? readyBusyText : "待機中")
                    Text(model.ttsModel.label).foregroundStyle(.secondary)
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).lineLimit(2)
                Button {
                    model.retryEngine()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("もう一度試す")
            }
            Spacer(minLength: 0)
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定（モデルの切り替え）")
        }
        .font(.caption)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private var readyBusyText: String {
        model.queuedCount > 0 ? "生成中（あと\(model.queuedCount)本）" : "生成中"
    }
}
