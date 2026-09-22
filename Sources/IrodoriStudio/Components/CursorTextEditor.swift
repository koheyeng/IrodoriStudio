import AppKit
import SwiftUI

/// 絵文字ボタンなどから、テキスト欄のカーソル位置に文字を差し込むための窓口。
/// 親ビューで `@State private var insertion = TextInsertionProxy()` として持ち、
/// `CursorTextEditor(text:proxy:)` と `EmojiPaletteView { insertion.insert($0) }` の両方に渡す。
@MainActor
final class TextInsertionProxy {
    fileprivate weak var textView: NSTextView?
    /// テキスト欄がまだ無いときの逃げ道（末尾に足す）
    fileprivate var appendFallback: ((String) -> Void)?

    /// カーソル位置（範囲選択中なら置き換え）に差し込み、カーソルを差し込んだ文字の後ろへ進める。
    /// 同じ絵文字を連打すると、そのまま重なって入る。
    func insert(_ string: String) {
        guard let textView else {
            appendFallback?(string)
            return
        }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(string, replacementRange: textView.selectedRange())
    }
}

/// カーソル位置を覚えておける複数行テキスト欄（SwiftUI の TextEditor は挿入位置を外から扱いにくいので NSTextView を包む）
struct CursorTextEditor: NSViewRepresentable {
    @Binding var text: String
    var proxy: TextInsertionProxy?
    var fontSize: CGFloat = 15

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text
        proxy?.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        proxy?.textView = textView
        let binding = $text
        proxy?.appendFallback = { binding.wrappedValue += $0 }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
