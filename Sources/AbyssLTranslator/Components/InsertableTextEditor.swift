import AppKit
import SwiftUI

/// NSTextView wrapper that supports programmatic insertion at the caret.
struct InsertableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsertion: String?
    @Binding var selectedText: String
    var fontSize = AppSettingsStore.defaultEditorFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.isEditable = true
        textView.allowsUndo = true
        applyFont(to: textView)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        applyFont(to: textView)

        if let insert = pendingInsertion, !insert.isEmpty {
            let selected = textView.selectedRange()
            textView.insertText(insert, replacementRange: selected)
            pendingInsertion = nil
            text = textView.string
            return
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let maxLocation = (textView.string as NSString).length
            let clampedLocation = min(selected.location, maxLocation)
            let clampedLength = min(selected.length, max(0, maxLocation - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
        }
    }

    private func applyFont(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
        if textView.font?.pointSize != font.pointSize {
            textView.font = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InsertableTextEditor
        weak var textView: NSTextView?

        init(_ parent: InsertableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateSelectedText(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateSelectedText(for: textView)
        }

        private func updateSelectedText(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0,
                  NSMaxRange(selectedRange) <= (textView.string as NSString).length
            else {
                parent.selectedText = ""
                return
            }
            parent.selectedText = (textView.string as NSString).substring(with: selectedRange)
        }
    }
}
