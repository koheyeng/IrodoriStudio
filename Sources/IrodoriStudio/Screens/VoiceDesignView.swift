import IrodoriKit
import SwiftUI

/// 声づくり（単発で焼く）。左で声の設定、右でセリフと結果を扱う。
struct VoiceDesignView: View {
    @Environment(AppModel.self) private var model
    @State private var insertion = TextInsertionProxy()
    @State private var isShowingSaveSheet = false
    @State private var referenceName = ""

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 0) {
            VoiceProfileEditor(profile: $model.design.voice)
                .frame(width: 360)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 生成・結果をスクロールせずに見せたいので、この2つを上に固め、長くなりがちな絵文字パレットは下に置く
                    lineSection(text: $model.design.text)
                    if let clip = model.clip(model.design.lastClipID) {
                        resultSection(clip)
                    }
                    EmojiPaletteView { insertion.insert($0) }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("声づくり")
        .sheet(isPresented: $isShowingSaveSheet) {
            saveSheet
        }
    }

    // MARK: - セリフ

    private func lineSection(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("セリフ")
                .font(.headline)
            CursorTextEditor(text: text, proxy: insertion)
                .frame(height: 140)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

            // 文字数・注意文（左）と 生成ボタン・状態（右）を1行にまとめて、縦の高さを詰める
            HStack(spacing: 12) {
                Text("\(text.wrappedValue.count)文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if text.wrappedValue.count > LineLength.recommendedMax {
                    Label(LineLength.warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button {
                    model.generateDesign()
                } label: {
                    Label("生成", systemImage: "waveform")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.design.status.isBusy || text.wrappedValue.isEmpty)

                StatusBadge(status: model.design.status)

                if case .loading = model.engineState {
                    Label("モデル読み込み中", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 結果

    private func resultSection(_ clip: GeneratedClip) -> some View {
        GroupBox("結果") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    PlayButton(url: clip.audioURL)
                    WaveformView(url: clip.audioURL)
                        .frame(height: 40)
                    Text(clip.duration.secondsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label("seed \(clip.seed)", systemImage: "number")
                    if let referenceName = clip.referenceName {
                        Label(referenceName, systemImage: "lock.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let caption = clip.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("キャプション無しで生成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("見本に保存…") {
                        referenceName = ""
                        isShowingSaveSheet = true
                    }
                    Button("完成音声で見る") {
                        model.selection = .clips
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("声の見本として保存")
                .font(.headline)
            TextField("見本の名前", text: $referenceName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("キャンセル") { isShowingSaveSheet = false }
                Button("保存") {
                    model.saveDesignAsReference(name: referenceName)
                    isShowingSaveSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(referenceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
