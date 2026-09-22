import IrodoriKit
import SwiftUI

/// 絵文字の演技指導パレット。押すと `onInsert` に絵文字を渡す（カーソル位置への挿入は呼ぶ側で）。
struct EmojiPaletteView: View {
    var onInsert: (String) -> Void

    /// カテゴリ名の固定幅。狭い幅（台本インスペクタの300pt前後）でも右側の折り返しが確保できるように小さめ
    private let categoryLabelWidth: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("絵文字は音を入れる記号。押すとカーソル位置に入り、重ねるほど強く・長くなる", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(EmojiCategory.allCases) { category in
                HStack(alignment: .top, spacing: 8) {
                    Text(category.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: categoryLabelWidth, alignment: .leading)
                    FlowLayout(spacing: 4) {
                        ForEach(EmojiPalette.items(in: category)) { item in
                            EmojiButton(item: item) { onInsert(item.emoji) }
                        }
                    }
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let item: EmojiItem
    let action: () -> Void
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
        .onHover { isHovering = $0 }
        .help(item.tooltip)
        .accessibilityLabel(item.tooltip)
    }
}
