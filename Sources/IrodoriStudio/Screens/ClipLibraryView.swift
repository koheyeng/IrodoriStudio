import AppKit
import IrodoriKit
import SwiftUI

/// 完成音声一覧。生成済みの音声をまとめて見る・絞り込む・書き出す。
struct ClipLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AudioPlayer.self) private var player

    @State private var selection: Set<GeneratedClip.ID> = []
    @State private var sourceFilter: SourceFilter = .all
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\GeneratedClip.createdAt, order: .reverse)]

    var body: some View {
        Group {
            if model.clips.isEmpty {
                ContentUnavailableView("完成音声はまだありません", systemImage: "music.note.list")
            } else if filteredClips.isEmpty {
                ContentUnavailableView.search
            } else {
                VStack(spacing: 0) {
                    table
                    if let clip = selectedClip {
                        Divider()
                        ClipDetailPanel(clip: clip)
                    }
                }
            }
        }
        .navigationTitle("完成音声")
        .searchable(text: $searchText, prompt: "セリフ・キャプションで検索")
        .onChange(of: sourceFilter) { _, _ in syncSelectionToVisible() }
        .onChange(of: searchText) { _, _ in syncSelectionToVisible() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("由来", selection: $sourceFilter) {
                    Text("すべて").tag(SourceFilter.all)
                    Text("声づくり").tag(SourceFilter.voiceDesign)
                    ForEach(model.projects) { project in
                        Text(project.name).tag(SourceFilter.project(project.id))
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    revealInFinder(selection)
                } label: {
                    Label("Finderで表示", systemImage: "folder")
                }
                .disabled(selection.isEmpty)
                Button {
                    export(selection)
                } label: {
                    Label("書き出し…", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Button {
                    removeFromList(selection)
                } label: {
                    Label("一覧から外す", systemImage: "minus.circle")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private var table: some View {
        Table(filteredClips, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { clip in
                PlayButton(url: clip.audioURL, size: 18)
            }
            .width(28)

            TableColumn("セリフ", value: \.text) { clip in
                Text(clip.text).lineLimit(1)
            }
            .width(min: 160, ideal: 320)
            TableColumn("キャラ", value: \.characterLabel) { clip in
                if clip.characterName == nil {
                    Text(clip.characterLabel).foregroundStyle(.tertiary)
                } else {
                    Text(clip.characterLabel)
                }
            }
            .width(min: 70, ideal: 90)
            TableColumn("台本", value: \.sourceLabel) { clip in
                Text(clip.sourceLabel)
            }
            .width(min: 90, ideal: 140)
            TableColumn("seed", value: \.seed) { clip in
                Text("\(clip.seed)")
            }
            .width(40)
            TableColumn("長さ", value: \.duration) { clip in
                Text(clip.duration.secondsLabel)
            }
            .width(60)
            TableColumn("作成日時", value: \.createdAt) { clip in
                Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: GeneratedClip.ID.self) { ids in
            Button("Finderで表示") { revealInFinder(ids) }
            Button("書き出し…") { export(ids) }
            Divider()
            Button("一覧から外す", role: .destructive) { removeFromList(ids) }
        } primaryAction: { ids in
            playFirst(ids)
        }
    }

    // MARK: - 絞り込み

    private enum SourceFilter: Hashable {
        case all
        case voiceDesign
        case project(Project.ID)
    }

    private var filteredClips: [GeneratedClip] {
        var clips = model.clips
        switch sourceFilter {
        case .all: break
        case .voiceDesign: clips = clips.filter { $0.source == .voiceDesign }
        case .project(let id):
            clips = clips.filter { if case .project(let projectID, _) = $0.source { return projectID == id } else { return false } }
        }
        guard !searchText.isEmpty else { return clips.sorted(using: sortOrder) }
        return clips.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) || ($0.caption ?? "").localizedCaseInsensitiveContains(searchText)
        }.sorted(using: sortOrder)
    }

    private var selectedClip: GeneratedClip? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return model.clip(id)
    }

    /// 絞り込み・検索で見えなくなった行は選択から外す（詳細パネルや操作が非表示の行に効かないように）
    private func syncSelectionToVisible() {
        selection.formIntersection(Set(filteredClips.map(\.id)))
    }

    // MARK: - 操作

    private func playFirst(_ ids: Set<GeneratedClip.ID>) {
        guard let id = ids.first, let clip = model.clip(id) else { return }
        player.toggle(clip.audioURL)
    }

    private func revealInFinder(_ ids: Set<GeneratedClip.ID>) {
        let urls = ids.compactMap { model.clip($0)?.audioURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func removeFromList(_ ids: Set<GeneratedClip.ID>) {
        // モックなのでファイルは消さず、一覧から外すだけ
        model.clips.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    private func export(_ ids: Set<GeneratedClip.ID>) {
        let clips = ids.compactMap { model.clip($0) }
        guard !clips.isEmpty else { return }
        if clips.count == 1, let clip = clips.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = exportFilename(index: 1, clip: clip)
            panel.begin { response in
                guard response == .OK, let destination = panel.url else { return }
                try? FileManager.default.copyItem(at: clip.audioURL, to: destination)
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "書き出し"
            panel.begin { response in
                guard response == .OK, let folder = panel.url else { return }
                for (offset, clip) in clips.enumerated() {
                    let destination = folder.appendingPathComponent(exportFilename(index: offset + 1, clip: clip))
                    try? FileManager.default.copyItem(at: clip.audioURL, to: destination)
                }
            }
        }
    }

    private func exportFilename(index: Int, clip: GeneratedClip) -> String {
        let head = String(clip.text.prefix(10)).replacingOccurrences(of: "/", with: "／")
        return "\(index)_\(clip.characterLabel)_\(head).wav"
    }
}

/// 選んだ1本の詳細
private struct ClipDetailPanel: View {
    let clip: GeneratedClip

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                WaveformView(url: clip.audioURL)
                    .frame(height: 40)
                HStack {
                    PlayButton(url: clip.audioURL)
                    Text(clip.duration.secondsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.text)
                    .font(.callout)
                if let caption = clip.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let referenceName = clip.referenceName {
                    Label(referenceName, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(clip.audioURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding()
    }
}

private extension GeneratedClip {
    // 声づくりで焼いたもの（キャラ無し）は「台本」列にすでに「声づくり」と出るので、ここは「—」にして二重表示を避ける
    var characterLabel: String { characterName ?? "—" }

    var sourceLabel: String {
        switch source {
        case .voiceDesign: return "声づくり"
        case .project(_, let name): return name
        }
    }
}
