import IrodoriKit
import SwiftUI

/// 声の見本（リファレンス）一覧。カードから声づくりへ読み込んで使う。
struct ReferenceLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var ageFilter: AgeFeel?
    @State private var selectedMoods: Set<Mood> = []
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterBar
                if filteredReferences.isEmpty {
                    emptyView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(filteredReferences) { reference in
                            ReferenceCard(reference: reference)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("声の見本")
        .searchable(text: $searchText, prompt: "名前・キャプションで検索")
        .toolbar {
            ToolbarItem {
                Button {
                    model.selection = .voiceDesign
                } label: {
                    Label("見本を作る", systemImage: "plus")
                }
                .help("声づくり画面で焼いてから「見本に保存」すると、ここに追加されます")
            }
        }
    }

    // MARK: - 絞り込み

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("年齢感", selection: $ageFilter) {
                Text("すべて").tag(AgeFeel?.none)
                ForEach(AgeFeel.allCases) { age in
                    Text(age.label).tag(Optional(age))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            FlowLayout(spacing: 6) {
                ForEach(Mood.allCases) { mood in
                    MoodChip(mood: mood, isSelected: selectedMoods.contains(mood)) {
                        toggleMoodFilter(mood)
                    }
                }
            }
        }
    }

    private func toggleMoodFilter(_ mood: Mood) {
        if selectedMoods.contains(mood) {
            selectedMoods.remove(mood)
        } else {
            selectedMoods.insert(mood)
        }
    }

    private var filteredReferences: [VoiceReference] {
        model.references.filter { reference in
            (ageFilter == nil || reference.settings.age == ageFilter)
                && selectedMoods.isSubset(of: reference.settings.moods)
                && (searchText.isEmpty
                    || reference.name.localizedCaseInsensitiveContains(searchText)
                    || reference.caption.localizedCaseInsensitiveContains(searchText))
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if model.references.isEmpty {
            ContentUnavailableView(
                "声の見本がまだありません", systemImage: "square.stack.3d.up",
                description: Text("声づくり画面で焼いてから「見本に保存」すると、ここに並びます")
            )
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                "条件に合う見本がありません", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("絞り込みを変えてみてください")
            )
        }
    }
}

/// 見本1件分のカード。
private struct ReferenceCard: View {
    let reference: VoiceReference
    @Environment(AppModel.self) private var model
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(reference.name)
                    .font(.headline)
                    .lineLimit(1)

                tagRow

                Text(reference.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(reference.sampleText)
                    .font(.callout)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    PlayButton(url: reference.audioURL)
                    WaveformView(url: reference.audioURL)
                        .frame(height: 32)
                    Text("seed \(reference.settings.seed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !fixedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(fixedUsers, id: \.self) { line in
                            Text("🔒 \(line)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("声づくりで使う") {
                    model.applyReferenceToDesign(reference)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        // LazyVGrid は既定だと行内で縦中央寄せになるので、上揃え＆同じ行の高さを揃える
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button("名前を変更") {
                renameText = reference.name
                isRenaming = true
            }
            Divider()
            Button("削除", role: .destructive) {
                model.deleteReference(reference.id)
            }
        }
        .alert("名前を変更", isPresented: $isRenaming) {
            TextField("名前", text: $renameText)
            Button("キャンセル", role: .cancel) {}
            Button("変更") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { model.renameReference(reference.id, to: trimmed) }
            }
        }
    }

    private var tagRow: some View {
        FlowLayout(spacing: 4) {
            tag(reference.settings.gender.label)
            tag(reference.settings.age.label)
            tag(reference.settings.pitch.label)
            ForEach(reference.settings.orderedMoods) { mood in
                tag(mood.label)
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    /// どの台本のどのキャラが、この見本で声を固定しているか
    private var fixedUsers: [String] {
        model.projects.flatMap { project in
            project.characters.compactMap { character in
                character.voice.fixedReferenceID == reference.id ? "\(project.name)／\(character.name)" : nil
            }
        }
    }
}
