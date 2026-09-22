import IrodoriKit
import SwiftUI

/// 声の設定（性別・年齢感・雰囲気・高さ・seed → キャプション、声の見本の読み込みと固定）を編集する部品。
/// 声づくり画面と、台本の登場キャラ編集で共通に使う。320〜420pt 程度の縦長でも崩れないように、
/// 雰囲気だけは segmented ではなく折り返すチップにしている。
struct VoiceProfileEditor: View {
    @Binding var profile: VoiceProfile
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("声の設定") {
                Picker("性別", selection: $profile.settings.gender) {
                    ForEach(Gender.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("年齢感", selection: $profile.settings.age) {
                    ForEach(AgeFeel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("声の高さ", selection: $profile.settings.pitch) {
                    ForEach(Pitch.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("雰囲気（複数選択可）")
                        .font(.subheadline)
                    FlowLayout(spacing: 6) {
                        ForEach(Mood.allCases) { mood in
                            MoodChip(mood: mood, isSelected: profile.settings.moods.contains(mood)) {
                                toggleMood(mood)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // ラベルは LabeledContent の1つだけに任せる（中の TextField/Stepper は無題にして二重表示を防ぐ）
                    LabeledContent("seed") {
                        HStack(spacing: 8) {
                            TextField("", value: $profile.settings.seed, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 76)
                            Stepper("", value: $profile.settings.seed, in: VoiceSettings.seedRange)
                                .labelsHidden()
                            Button {
                                profile.settings.seed = Int.random(in: VoiceSettings.seedRange)
                            } label: {
                                Text("🎲")
                            }
                            .buttonStyle(.plain)
                            .help("seedをランダムに変える")
                        }
                    }
                    Text("seedは口調・態度を決める／声質はキャプションで")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("キャプション") {
                captionEditor
                captionStatusRow
                if profile.caption.isEmpty {
                    Text("キャプション無し（声質・話し方の指定なしで生成）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("声の見本") {
                referenceMenuRow
                if let name = model.reference(profile.referenceID)?.name {
                    Label(name, systemImage: "waveform.circle")
                        .font(.callout)
                } else {
                    Text("見本は未選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("この声で固定（参照音声にする）", isOn: referenceFixedBinding)
                    .disabled(profile.referenceID == nil)

                if profile.isReferenceFixed {
                    Text("声質は見本の音声に任せて、キャプションは話し方だけにしています")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: profile.settings) { _, _ in
            profile.refreshCaptionIfAuto()
        }
    }

    // MARK: - キャプション

    private var captionEditor: some View {
        // TextField はタイトルを Form の行ラベルとして左に出してしまう（セクション見出しと二重になる）ので
        // ラベルを持たない TextEditor で、幅いっぱいの左寄せ・複数行にする
        TextEditor(text: captionBinding)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 72, maxHeight: 112)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
    }

    private var captionStatusRow: some View {
        HStack {
            Text(profile.isCaptionEdited ? "手で編集中" : "設定から自動作成")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("設定から作り直す") {
                profile.resetCaptionToAuto()
            }
            .disabled(!profile.isCaptionEdited)
        }
    }

    /// 書き換えたら isCaptionEdited を立てる（自動更新を止める）。programmatic な更新はここを通らない。
    private var captionBinding: Binding<String> {
        Binding(
            get: { profile.caption },
            set: { newValue in
                profile.caption = newValue
                profile.isCaptionEdited = true
            }
        )
    }

    // MARK: - 声の見本

    private var referenceMenuRow: some View {
        Menu("見本から読み込む") {
            if model.references.isEmpty {
                Text("見本がありません")
            } else {
                ForEach(model.references) { reference in
                    Button(reference.name) { profile.load(reference) }
                }
            }
        }
    }

    private var referenceFixedBinding: Binding<Bool> {
        Binding(
            get: { profile.isReferenceFixed },
            set: { profile.setReferenceFixed($0) }
        )
    }

    // MARK: - 雰囲気チップ

    private func toggleMood(_ mood: Mood) {
        if profile.settings.moods.contains(mood) {
            profile.settings.moods.remove(mood)
        } else {
            profile.settings.moods.insert(mood)
        }
    }
}
