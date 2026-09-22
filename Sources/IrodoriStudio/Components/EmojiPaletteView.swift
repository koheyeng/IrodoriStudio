import IrodoriKit
import SwiftUI

/// 絵文字の演技指導パレット。押すと `onInsert` に絵文字を渡す（カーソル位置への挿入は呼ぶ側で）。
struct EmojiPaletteView: View {
    var onInsert: (String) -> Void

    /// カテゴリ名の固定幅。狭い幅（台本インスペクタの300pt前後）でも右側の折り返しが確保できるように小さめ
    private let categoryLabelWidth: CGFloat = 80
    /// マウスが乗っている絵文字。上の説明欄に効果を出す
    @State private var hoveredItem: EmojiItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            description
            ForEach(EmojiCategory.allCases) { category in
                HStack(alignment: .top, spacing: 8) {
                    Text(category.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: categoryLabelWidth, alignment: .leading)
                    FlowLayout(spacing: 4) {
                        ForEach(EmojiPalette.items(in: category)) { item in
                            EmojiButton(item: item) {
                                onInsert(item.emoji)
                            } onHover: { hovering in
                                if hovering {
                                    hoveredItem = item
                                } else if hoveredItem == item {
                                    hoveredItem = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// システムのツールチップは出るまで間があるので、ホバーした瞬間に効果が読めるよう専用の欄に出す。
    /// 高さを固定して、出たり消えたりしてもパレットがずれないようにする
    private var description: some View {
        Group {
            if let item = hoveredItem {
                HStack(spacing: 10) {
                    Text(item.emoji)
                        .font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.callout.weight(.semibold))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("絵文字は音を入れる記号。押すとカーソル位置に入り、重ねるほど強く・長くなる", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

private struct EmojiButton: View {
    let item: EmojiItem
    let action: () -> Void
    let onHover: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(item.emoji)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .help(item.tooltip)
        .accessibilityLabel(item.tooltip)
    }
}
