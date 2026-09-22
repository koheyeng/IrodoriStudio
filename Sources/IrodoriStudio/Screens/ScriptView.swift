import IrodoriKit
import SwiftUI

/// 台本（1プロジェクト分）。キャラの帯・セリフ行のリスト・選んだ行のインスペクタで構成する。
struct ScriptView: View {
    let projectID: Project.ID
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let index = model.projectIndex(projectID) {
            ScriptContentView(project: $model.projects[index])
        } else {
            ContentUnavailableView("台本が見つかりません", systemImage: "doc.questionmark")
                .navigationTitle("台本")
        }
    }
}

private struct ScriptContentView: View {
    @Binding var project: Project
    @Environment(AppModel.self) private var model

    @State private var selectedLineID: ScriptLine.ID?
    @State private var showInspector = true
    @State private var editingCharacterID: CastMember.ID?
    @State private var insertion = TextInsertionProxy()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            castStrip
            Divider()
            if project.characters.isEmpty && project.lines.isEmpty {
                emptyState
            } else {
                lineList
            }
        }
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .sheet(isPresented: characterSheetPresented) {
            if let editingCharacterID, let index = project.characters.firstIndex(where: { $0.id == editingCharacterID }) {
                CharacterEditSheet(character: $project.characters[index])
            }
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        let generatedCount = project.lines.filter { $0.status == .generated }.count
        let totalDuration = project.lines.reduce(TimeInterval(0)) { total, line in
            guard line.status == .generated, let clip = model.clip(line.clipID) else { return total }
            return total + clip.duration
        }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.title2.bold())
                Text("\(project.lines.count)行 ・ 生成済み \(generatedCount)/\(project.lines.count) ・ 合計 \(totalDuration.secondsLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 4)
    }

    // MARK: - 登場キャラの帯

    private var castStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.characters) { character in
                    CastChip(character: character, referenceName: model.reference(character.voice.fixedReferenceID)?.name)
                        .onTapGesture { editingCharacterID = character.id }
                        .contextMenu {
                            Button("削除", role: .destructive) { removeCharacter(character.id) }
                        }
                }
                Button {
                    addCharacter()
                } label: {
                    Label("キャラ", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var characterSheetPresented: Binding<Bool> {
        Binding(get: { editingCharacterID != nil }, set: { if !$0 { editingCharacterID = nil } })
    }

    private func addCharacter() {
        let character = CastMember(name: "キャラ\(project.characters.count + 1)", colorIndex: project.characters.count, voice: VoiceProfile())
        project.characters.append(character)
        editingCharacterID = character.id
    }

    private func removeCharacter(_ id: CastMember.ID) {
        project.characters.removeAll { $0.id == id }
        for index in project.lines.indices where project.lines[index].characterID == id {
            project.lines[index].characterID = nil
            // 声の出所が消えたので、生成済みなら「変更あり」として未生成に戻す
            if project.lines[index].status == .generated {
                project.lines[index].status = .notGenerated
            }
        }
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        ContentUnavailableView {
            Label("台本はまだ空です", systemImage: "theatermasks")
        } description: {
            Text("キャラを追加して、セリフの行を作りましょう")
        } actions: {
            Button("キャラを追加") { addCharacter() }
            Button("行を追加") { addLine() }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - セリフ行のリスト

    private var lineList: some View {
        List(selection: $selectedLineID) {
            ForEach(Array(project.lines.enumerated()), id: \.element.id) { offset, line in
                LineRow(
                    line: line,
                    character: project.character(line.characterID),
                    characters: project.characters,
                    index: offset + 1,
                    clip: model.clip(line.clipID),
                    characterID: invalidatingBinding(lineID: line.id, keyPath: \.characterID, default: nil),
                    onGenerate: { model.generateLine(projectID: project.id, lineID: line.id) }
                )
                .tag(line.id)
                .contextMenu {
                    Button("この行を生成") { model.generateLine(projectID: project.id, lineID: line.id) }
                        .disabled(line.status.isBusy)
                    Button("複製") { duplicateLine(line.id) }
                    Divider()
                    Button("削除", role: .destructive) { deleteLine(line.id) }
                }
            }
            .onMove { indices, newOffset in
                project.lines.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
        .listStyle(.inset)
    }

    private func addLine() {
        let characterID = selectedLineID.flatMap { id in project.lines.first { $0.id == id }?.characterID }
            ?? project.lines.last?.characterID
        let newLine = ScriptLine(characterID: characterID, text: "")
        if let selectedLineID, let index = project.lines.firstIndex(where: { $0.id == selectedLineID }) {
            project.lines.insert(newLine, at: index + 1)
        } else {
            project.lines.append(newLine)
        }
        selectedLineID = newLine.id
    }

    private func duplicateLine(_ lineID: ScriptLine.ID) {
        guard let index = project.lines.firstIndex(where: { $0.id == lineID }) else { return }
        let source = project.lines[index]
        let copy = ScriptLine(
            characterID: source.characterID, text: source.text,
            captionOverride: source.captionOverride, seedOverride: source.seedOverride
        )
        project.lines.insert(copy, at: index + 1)
        selectedLineID = copy.id
    }

    private func deleteLine(_ lineID: ScriptLine.ID) {
        // 消す前に必ず取り消す（順番待ちなら取り消し、生成中なら焼き上がっても捨てる）
        model.cancelLine(projectID: project.id, lineID: lineID)
        project.lines.removeAll { $0.id == lineID }
        if selectedLineID == lineID { selectedLineID = nil }
    }

    // MARK: - ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { addLine() } label: {
                Label("行を追加", systemImage: "plus.bubble")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isBusy {
                Button {
                    model.cancelQueued(projectID: project.id)
                } label: {
                    Label("止める", systemImage: "stop.fill")
                }
                .help("待機中の行を取り消します（生成中の1本はそのまま焼き切ります）")
            } else {
                Button {
                    model.generateAll(projectID: project.id)
                } label: {
                    Label("すべて生成", systemImage: "waveform.badge.plus")
                }
                .disabled(project.lines.isEmpty)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showInspector.toggle() } label: {
                Label("インスペクタ", systemImage: "sidebar.right")
            }
        }
    }

    private var isBusy: Bool {
        project.lines.contains { $0.status.isBusy }
    }

    // MARK: - インスペクタ

    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedLineID, let index = project.lines.firstIndex(where: { $0.id == selectedLineID }) {
            let line = project.lines[index]
            LineInspector(
                line: line,
                character: project.character(line.characterID),
                characters: project.characters,
                clip: model.clip(line.clipID),
                insertion: insertion,
                text: invalidatingBinding(lineID: selectedLineID, keyPath: \.text, default: ""),
                captionOverride: invalidatingBinding(lineID: selectedLineID, keyPath: \.captionOverride, default: nil),
                seedOverride: invalidatingBinding(lineID: selectedLineID, keyPath: \.seedOverride, default: nil),
                characterID: invalidatingBinding(lineID: selectedLineID, keyPath: \.characterID, default: nil),
                onGenerate: { model.generateLine(projectID: project.id, lineID: selectedLineID) }
            )
            .id(selectedLineID)
        } else {
            ContentUnavailableView("行を選んでください", systemImage: "text.cursor")
                .frame(minWidth: 280)
        }
    }

    // MARK: - 行の編集（生成済みなら未生成に戻す）

    /// セリフ・キャプション・seed・キャラのどれかを変えたら、生成済みの行は「変更あり」として未生成に戻す
    /// （古い clipID はそのまま残すので、変更前の音声の再生はできる）。
    private func invalidatingBinding<T: Equatable>(
        lineID: ScriptLine.ID, keyPath: WritableKeyPath<ScriptLine, T>, default defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { project.lines.first(where: { $0.id == lineID })?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                guard let index = project.lines.firstIndex(where: { $0.id == lineID }) else { return }
                guard project.lines[index][keyPath: keyPath] != newValue else { return }
                project.lines[index][keyPath: keyPath] = newValue
                if project.lines[index].status == .generated {
                    project.lines[index].status = .notGenerated
                }
            }
        )
    }
}

// MARK: - 登場キャラのチップ

private struct CastChip: View {
    let character: CastMember
    let referenceName: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CastColor.color(character.colorIndex))
                .frame(width: 10, height: 10)
            Text(character.name)
                .fontWeight(.medium)
            if let referenceName {
                HStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                    Text(referenceName)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .contentShape(Capsule())
    }
}

private struct CharacterEditSheet: View {
    @Binding var character: CastMember
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("名前") {
                    TextField("名前", text: $character.name)
                }
                Section("色") {
                    ColorSwatchPicker(colorIndex: $character.colorIndex)
                }
                Section("声") {
                    VoiceProfileEditor(profile: $character.voice)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("完了") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 520)
    }
}

private struct ColorSwatchPicker: View {
    @Binding var colorIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CastColor.palette.indices, id: \.self) { index in
                Circle()
                    .fill(CastColor.palette[index])
                    .frame(width: 22, height: 22)
                    .overlay {
                        if index == colorIndex {
                            Circle().strokeBorder(Color.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture { colorIndex = index }
            }
        }
    }
}

// MARK: - セリフ行の1列

private struct LineRow: View {
    let line: ScriptLine
    let character: CastMember?
    let characters: [CastMember]
    let index: Int
    let clip: GeneratedClip?
    @Binding var characterID: CastMember.ID?
    let onGenerate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            Capsule()
                .fill(character.map { CastColor.color($0.colorIndex) } ?? Color.secondary.opacity(0.3))
                .frame(width: 4)
            Picker("", selection: $characterID) {
                Text("未設定").tag(CastMember.ID?.none)
                ForEach(characters) { member in
                    Text(member.name).tag(Optional(member.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.text.isEmpty ? "（セリフ未入力）" : line.text)
                    .lineLimit(2)
                    .foregroundStyle(line.text.isEmpty ? Color.secondary : Color.primary)
                overrideMarks
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(status: line.status)
            PlayButton(url: clip?.audioURL, size: 18)
            Button(action: onGenerate) {
                Image(systemName: "waveform.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(line.status.isBusy)
            .help("この行だけ生成")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var overrideMarks: some View {
        if line.seedOverride != nil || line.captionOverride != nil {
            HStack(spacing: 8) {
                if let seed = line.seedOverride {
                    Label("seed \(seed)", systemImage: "number")
                }
                if line.captionOverride != nil {
                    Label("キャプション上書き", systemImage: "text.badge.star")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 選んだ行のインスペクタ

private struct LineInspector: View {
    let line: ScriptLine
    let character: CastMember?
    let characters: [CastMember]
    let clip: GeneratedClip?
    let insertion: TextInsertionProxy
    @Binding var text: String
    @Binding var captionOverride: String?
    @Binding var seedOverride: Int?
    @Binding var characterID: CastMember.ID?
    let onGenerate: () -> Void

    @State private var useCharacterCaption = true
    @State private var useCharacterSeed = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                characterSection
                captionAndSeedSection
                textSection
                resultSection
                EmojiPaletteView { insertion.insert($0) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            useCharacterCaption = captionOverride == nil
            useCharacterSeed = seedOverride == nil
        }
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("キャラ").font(.headline)
            Picker("キャラ", selection: $characterID) {
                Text("未設定").tag(CastMember.ID?.none)
                ForEach(characters) { member in
                    Text(member.name).tag(Optional(member.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// キャプションと seed は縦に詰めて表示（声づくり画面と揃える）
    private var captionAndSeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("キャラのキャプションを使う", isOn: Binding(
                    get: { useCharacterCaption },
                    set: { newValue in
                        useCharacterCaption = newValue
                        captionOverride = newValue ? nil : (character?.voice.caption ?? "")
                    }
                ))
                .disabled(character == nil)
                if useCharacterCaption {
                    Text(character?.voice.caption ?? "（キャラ未設定）")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("キャプション", text: Binding(get: { captionOverride ?? "" }, set: { captionOverride = $0 }), axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Toggle("キャラの seed を使う", isOn: Binding(
                    get: { useCharacterSeed },
                    set: { newValue in
                        useCharacterSeed = newValue
                        seedOverride = newValue ? nil : (character?.voice.settings.seed ?? 1)
                    }
                ))
                .disabled(character == nil)
                Spacer()
                if useCharacterSeed {
                    Text("seed \(character?.voice.settings.seed ?? 1)")
                        .foregroundStyle(.secondary)
                } else {
                    Stepper(
                        value: Binding(get: { seedOverride ?? 1 }, set: { seedOverride = $0 }),
                        in: VoiceSettings.seedRange
                    ) {
                        Text("seed \(seedOverride ?? 1)")
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("セリフ").font(.headline)
            CursorTextEditor(text: $text, proxy: insertion)
                .frame(minHeight: 70, maxHeight: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            if text.count > LineLength.recommendedMax {
                Label(LineLength.warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Text("\(text.count)字")
                    .font(.caption)
                    .foregroundStyle(text.count > LineLength.recommendedMax ? Color.red : Color.secondary)
                Spacer()
                Button(action: onGenerate) {
                    Label(line.status.isBusy ? "生成中…" : "この行を生成", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(line.status.isBusy)
                StatusBadge(status: line.status)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch line.status {
        case .generated:
            if let clip {
                VStack(alignment: .leading, spacing: 6) {
                    WaveformView(url: clip.audioURL)
                        .frame(height: 44)
                    HStack {
                        PlayButton(url: clip.audioURL)
                        Text(clip.duration.secondsLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
