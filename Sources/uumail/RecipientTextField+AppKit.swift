import AppKit
import MailDomain
import Presentation
import SwiftUI

/// AppKit carriers for the recipient field and the candidate rows. Split out so the
/// public SwiftUI views in `RecipientTextField.swift` stay within the single-file budget.

extension RecipientTextField {
    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RecipientTextField
        weak var textField: NSTextField?
        var lastFocusRequest: Int?
        private var escapeMonitor: Any?

        init(_ parent: RecipientTextField) {
            self.parent = parent
        }

        func applyAppearance(to field: NSTextField, scale: CGFloat) {
            let factor = max(scale, 0.5)
            let font = NSFont.systemFont(ofSize: 13 * factor)
            field.font = font
            field.cell?.font = font
            field.backgroundColor = .textBackgroundColor
            field.textColor = .labelColor
            if let fitting = field as? RecipientFieldView {
                let height = 24 * factor
                if fitting.fittingHeight != height {
                    fitting.fittingHeight = height
                    fitting.invalidateIntrinsicContentSize()
                }
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            observeSelection()
            installEscapeMonitor()
            parent.onFocusChange(true)
            notifyCaret()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            stopObservingSelection()
            stopEscapeMonitor()
            parent.onFocusChange(false)
        }

        /// The field editor cancels an input-method composition before forwarding Esc
        /// to `doCommandBy`. A local monitor scoped to this focused field lets a visible
        /// candidate panel consume Esc first; with no candidates the event is passed on
        /// so the composition is cancelled normally.
        private func installEscapeMonitor() {
            guard escapeMonitor == nil else { return }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.keyCode == 53 else { return event }
                guard let editor = self.textField?.currentEditor() as? NSTextView,
                      editor.hasMarkedText()
                else { return event }
                return self.parent.onCommand(.dismiss) ? nil : event
            }
        }

        func stopEscapeMonitor() {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
            escapeMonitor = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = textField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                // Keep the binding and the suggestions untouched during composition.
                return
            }
            parent.text = field.stringValue
            parent.onTextChange(caretIsAtEnd())
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommand(.moveDown)
            case #selector(NSResponder.insertNewline(_:)):
                // Return must never bubble to the sheet's default (Send) button from an
                // address field. It commits only when the user moved the highlight.
                guard !textView.hasMarkedText() else { return false }
                _ = parent.onCommand(.commit)
                return true
            case #selector(NSResponder.insertTab(_:)):
                guard !textView.hasMarkedText() else { return false }
                return parent.onCommand(.commit)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCommand(.dismiss)
            default:
                return false
            }
        }

        private func observeSelection() {
            stopObservingSelection()
            guard let editor = textField?.currentEditor() else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged(_:)),
                name: NSTextView.didChangeSelectionNotification,
                object: editor
            )
        }

        func stopObservingSelection() {
            NotificationCenter.default.removeObserver(
                self,
                name: NSTextView.didChangeSelectionNotification,
                object: nil
            )
        }

        @objc private func selectionChanged(_ notification: Notification) {
            notifyCaret()
        }

        private func notifyCaret() {
            guard textField != nil else { return }
            parent.onCaretChange(caretIsAtEnd())
        }

        private func caretIsAtEnd() -> Bool {
            guard let field = textField, let editor = field.currentEditor() as? NSTextView else {
                return false
            }
            let length = (field.stringValue as NSString).length
            let range = editor.selectedRange()
            return range.length == 0 && range.location == length
        }
    }
}

/// `NSTextField` subclass that reports the 24pt-at-100% row height SwiftUI's `Form`
/// `TextField` uses, instead of the AppKit default (16pt for a borderless field).
final class RecipientFieldView: NSTextField {
    var fittingHeight: CGFloat = 24

    override var intrinsicContentSize: NSSize {
        NSSize(width: 100, height: fittingHeight)
    }
}

/// Fits the text at the same 4pt inset as the SwiftUI `TextField` carrier while leaving
/// the background and focus ring at full bounds.
final class RecipientFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: 4, dy: 4)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: rect.insetBy(dx: 4, dy: 4),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }
}
/// AppKit-backed candidate row. Two non-editable labels keep the rendered name and
/// address readable to the offscreen L2 probe, while the SwiftUI button owns the click.
struct RecipientSuggestionRow: NSViewRepresentable {
    let contact: ContactAddress
    let scale: CGFloat

    func makeNSView(context: Context) -> SuggestionRowView {
        SuggestionRowView()
    }

    func updateNSView(_ nsView: SuggestionRowView, context: Context) {
        nsView.configure(contact: contact, scale: scale)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SuggestionRowView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 24 * max(scale, 0.5))
    }
}

final class SuggestionRowView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let addressLabel = NSTextField(labelWithString: "")
    private var hasName = false
    private var factor: CGFloat = 1

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in [nameLabel, addressLabel] {
            label.isEditable = false
            label.isSelectable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.isBordered = false
            label.focusRingType = .none
            label.usesSingleLineMode = true
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
        }
        nameLabel.lineBreakMode = .byTruncatingTail
        addressLabel.lineBreakMode = .byTruncatingMiddle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The SwiftUI button around this view owns the click; the labels never consume it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(contact: ContactAddress, scale: CGFloat) {
        factor = max(scale, 0.5)
        hasName = contact.name.map { !$0.isEmpty } ?? false
        nameLabel.stringValue = contact.name ?? ""
        nameLabel.isHidden = !hasName
        nameLabel.font = .systemFont(ofSize: 13 * factor)
        nameLabel.textColor = .labelColor
        addressLabel.stringValue = contact.address
        addressLabel.font = .systemFont(ofSize: 12.5 * factor)
        addressLabel.textColor = .secondaryLabelColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        let gap: CGFloat = 6
        let labelHeight = min(bounds.height, 17 * factor)
        let y = (bounds.height - labelHeight) / 2
        let available = max(0, bounds.width - inset * 2)
        let nameWidth: CGFloat
        if hasName {
            nameWidth = min(nameLabel.intrinsicContentSize.width, available * 0.45)
            nameLabel.frame = NSRect(x: inset, y: y, width: nameWidth, height: labelHeight)
        } else {
            nameWidth = 0
            nameLabel.frame = .zero
        }
        let addressX = hasName ? inset + nameWidth + gap : inset
        addressLabel.frame = NSRect(
            x: addressX,
            y: y,
            width: max(0, bounds.width - addressX - inset),
            height: labelHeight
        )
    }
}
