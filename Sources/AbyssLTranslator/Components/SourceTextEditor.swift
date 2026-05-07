import AppKit
import SwiftUI

/// NSTextView wrapper for source input that avoids publishing SwiftUI state on every keystroke.
struct SourceTextEditor: NSViewRepresentable {
    @Binding var injectedText: String?
    var focusOnAppear = false
    var fontSize = AppSettingsStore.defaultEditorFontSize
    let onTextChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChanged: onTextChanged)
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
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if focusOnAppear {
            context.coordinator.requestInitialFocus(for: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.textView = textView
        context.coordinator.onTextChanged = onTextChanged
        applyFont(to: textView)
        if focusOnAppear {
            context.coordinator.requestInitialFocus(for: textView)
        }

        guard let newText = injectedText else { return }

        if textView.string != newText {
            let selected = textView.selectedRange()
            context.coordinator.isApplyingExternalText = true
            textView.string = newText
            context.coordinator.isApplyingExternalText = false

            let maxLocation = (textView.string as NSString).length
            let clampedLocation = min(selected.location, maxLocation)
            let clampedLength = min(selected.length, max(0, maxLocation - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
        }

        injectedText = nil
    }

    private func applyFont(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
        if textView.font?.pointSize != font.pointSize {
            textView.font = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChanged: (String) -> Void
        weak var textView: NSTextView?
        var isApplyingExternalText = false
        private var didRequestInitialFocus = false

        init(onTextChanged: @escaping (String) -> Void) {
            self.onTextChanged = onTextChanged
        }

        func requestInitialFocus(for textView: NSTextView) {
            guard !didRequestInitialFocus else { return }
            didRequestInitialFocus = true
            focus(textView, remainingAttempts: 8)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            onTextChanged(textView.string)
        }

        private func focus(_ textView: NSTextView, remainingAttempts: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textView] in
                guard let self, let textView else { return }
                if let window = textView.window {
                    window.makeFirstResponder(textView)
                } else if remainingAttempts > 0 {
                    self.focus(textView, remainingAttempts: remainingAttempts - 1)
                }
            }
        }
    }
}
