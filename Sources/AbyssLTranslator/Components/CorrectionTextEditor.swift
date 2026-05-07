import AppKit
import SwiftUI

/// NSTextView wrapper that underlines AI-corrected spans and lets users replace them.
struct CorrectionTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var corrections: [WritingCorrectionIssue]
    var fontSize = AppSettingsStore.defaultEditorFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, corrections: $corrections)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CorrectionNSTextView(frame: .zero)
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.correctionProvider = { context.coordinator.corrections.wrappedValue }
        textView.onCorrectionClick = { [weak coordinator = context.coordinator] correction, point in
            coordinator?.showMenu(for: correction, at: point)
        }
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.isEditable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.applyAttributedText(fontSize: fontSize)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CorrectionNSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.corrections = $corrections
        context.coordinator.textView = textView
        textView.correctionProvider = { context.coordinator.corrections.wrappedValue }

        if textView.string != text || context.coordinator.lastAppliedCorrections != corrections || context.coordinator.lastAppliedFontSize != fontSize {
            context.coordinator.applyAttributedText(fontSize: fontSize)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var corrections: Binding<[WritingCorrectionIssue]>
        weak var textView: CorrectionNSTextView?
        var lastAppliedCorrections: [WritingCorrectionIssue] = []
        var lastAppliedFontSize: Double = 0
        private var isApplyingProgrammaticChange = false

        init(text: Binding<String>, corrections: Binding<[WritingCorrectionIssue]>) {
            self.text = text
            self.corrections = corrections
        }

        func applyAttributedText(fontSize: Double) {
            guard let textView else { return }
            let selected = textView.selectedRange()
            let baseFont = NSFont.systemFont(ofSize: CGFloat(fontSize))
            let fullText = text.wrappedValue
            let fullLength = (fullText as NSString).length
            let attributed = NSMutableAttributedString(
                string: fullText,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor,
                ]
            )

            for correction in corrections.wrappedValue {
                guard let range = correction.range?.nsRange,
                      range.location >= 0,
                      range.length > 0,
                      NSMaxRange(range) <= fullLength
                else {
                    continue
                }

                attributed.addAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.systemRed,
                        .backgroundColor: NSColor.systemRed.withAlphaComponent(0.10),
                    ],
                    range: range
                )
            }

            textView.hideCorrectionTooltip()
            isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
            ]
            isApplyingProgrammaticChange = false

            let clampedLocation = min(selected.location, fullLength)
            let clampedLength = min(selected.length, max(0, fullLength - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            lastAppliedCorrections = corrections.wrappedValue
            lastAppliedFontSize = fontSize
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            text.wrappedValue = textView.string
            corrections.wrappedValue = []
            lastAppliedCorrections = []
            self.textView?.hideCorrectionTooltip()
        }

        func showMenu(for correction: WritingCorrectionIssue, at point: NSPoint) {
            guard let textView else { return }
            textView.hideCorrectionTooltip()
            let menu = NSMenu()

            for alternative in correction.alternatives {
                let item = NSMenuItem(
                    title: alternative,
                    action: #selector(applyReplacementFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = CorrectionMenuAction(id: correction.id, replacement: alternative)
                menu.addItem(item)
            }

            if !correction.alternatives.isEmpty {
                menu.addItem(.separator())
            }

            let restoreItem = NSMenuItem(
                title: String(localized: "writing.correction.restoreOriginal", bundle: .module),
                action: #selector(applyReplacementFromMenu(_:)),
                keyEquivalent: ""
            )
            restoreItem.target = self
            restoreItem.representedObject = CorrectionMenuAction(id: correction.id, replacement: correction.originalText)
            menu.addItem(restoreItem)
            menu.popUp(positioning: nil, at: point, in: textView)
        }

        @objc private func applyReplacementFromMenu(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? CorrectionMenuAction,
                  let textView,
                  let correctionIndex = corrections.wrappedValue.firstIndex(where: { $0.id == action.id }),
                  let range = corrections.wrappedValue[correctionIndex].range?.nsRange,
                  NSMaxRange(range) <= (textView.string as NSString).length
            else {
                return
            }

            let replacementLength = (action.replacement as NSString).length
            let delta = replacementLength - range.length

            isApplyingProgrammaticChange = true
            textView.textStorage?.replaceCharacters(in: range, with: action.replacement)
            isApplyingProgrammaticChange = false

            text.wrappedValue = textView.string
            var updated = corrections.wrappedValue
            updated.remove(at: correctionIndex)
            for index in updated.indices {
                guard var currentRange = updated[index].range else { continue }
                if currentRange.location > range.location {
                    currentRange.location += delta
                    updated[index].range = currentRange
                }
            }
            corrections.wrappedValue = updated
            applyAttributedText(fontSize: lastAppliedFontSize)
        }
    }
}

private final class CorrectionMenuAction: NSObject {
    let id: UUID
    let replacement: String

    init(id: UUID, replacement: String) {
        self.id = id
        self.replacement = replacement
    }
}

final class CorrectionNSTextView: NSTextView {
    var correctionProvider: (() -> [WritingCorrectionIssue])?
    var onCorrectionClick: ((WritingCorrectionIssue, NSPoint) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoveredCorrectionID: UUID?
    private var pendingTooltipWorkItem: DispatchWorkItem?
    private var tooltipWindow: NSWindow?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let correction = correction(at: point) else {
            hideCorrectionTooltip()
            return
        }

        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        if hoveredCorrectionID == correction.id, tooltipWindow != nil {
            positionTooltipWindow(near: screenPoint)
            return
        }

        hoveredCorrectionID = correction.id
        pendingTooltipWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showTooltip(correction.message, near: screenPoint)
        }
        pendingTooltipWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCorrectionTooltip()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hideCorrectionTooltip()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let correction = correction(at: point)
        else {
            super.mouseDown(with: event)
            return
        }

        onCorrectionClick?(correction, point)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager,
              let textContainer
        else {
            return nil
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < (string as NSString).length else { return nil }
        return characterIndex
    }

    private func correction(at point: NSPoint) -> WritingCorrectionIssue? {
        guard let characterIndex = characterIndex(at: point) else { return nil }
        return correctionProvider?().first { issue in
            guard let range = issue.range?.nsRange else { return false }
            return NSLocationInRange(characterIndex, range)
        }
    }

    func hideCorrectionTooltip() {
        pendingTooltipWorkItem?.cancel()
        pendingTooltipWorkItem = nil
        hoveredCorrectionID = nil
        tooltipWindow?.orderOut(nil)
        tooltipWindow = nil
    }

    private func showTooltip(_ message: String, near screenPoint: NSPoint) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let tooltipView = CorrectionTooltipView(message: message)
        let tooltipSize = tooltipView.fittingSize
        let tooltipFrame = tooltipFrame(size: tooltipSize, near: screenPoint)

        let window = NSWindow(
            contentRect: tooltipFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.contentView = tooltipView
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.orderFront(nil)
        tooltipWindow?.orderOut(nil)
        tooltipWindow = window
    }

    private func positionTooltipWindow(near screenPoint: NSPoint) {
        guard let tooltipWindow else { return }
        tooltipWindow.setFrame(tooltipFrame(size: tooltipWindow.frame.size, near: screenPoint), display: true)
    }

    private func tooltipFrame(size: NSSize, near screenPoint: NSPoint) -> NSRect {
        let visibleFrame = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: screenPoint.x + 12, y: screenPoint.y + 18)

        if origin.x + size.width > visibleFrame.maxX - 6 {
            origin.x = visibleFrame.maxX - size.width - 6
        }
        if origin.x < visibleFrame.minX + 6 {
            origin.x = visibleFrame.minX + 6
        }
        if origin.y + size.height > visibleFrame.maxY - 6 {
            origin.y = screenPoint.y - size.height - 18
        }
        if origin.y < visibleFrame.minY + 6 {
            origin.y = visibleFrame.minY + 6
        }

        return NSRect(origin: origin, size: size)
    }
}

private final class CorrectionTooltipView: NSView {
    private let textField: NSTextField

    init(message: String) {
        textField = NSTextField(labelWithString: message)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .labelColor
        textField.maximumNumberOfLines = 3
        textField.lineBreakMode = .byWordWrapping
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        frame = NSRect(origin: .zero, size: measuredSize(for: message))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var fittingSize: NSSize {
        frame.size
    }

    private func measuredSize(for message: String) -> NSSize {
        let maxWidth: CGFloat = 320
        let minWidth: CGFloat = 96
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
        ]
        let rect = NSAttributedString(string: message, attributes: attributes)
            .boundingRect(
                with: NSSize(width: maxWidth - 16, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        return NSSize(
            width: min(max(ceil(rect.width) + 16, minWidth), maxWidth),
            height: ceil(rect.height) + 12
        )
    }
}
