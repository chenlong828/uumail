import AppKit
import MailDomain
import Presentation
import SwiftUI

/// The keyboard commands the recipient field forwards before AppKit's default handling.
enum RecipientCommand: Equatable {
    case moveUp
    case moveDown
    case commit
    case dismiss
}

/// One address input: a borderless `NSTextField` shaped like the SwiftUI `TextField` it
/// replaces (24pt row at 100%, 13pt text, 4pt horizontal/vertical text inset, semantic
/// text background), plus the focus/caret/key-command hooks the suggestion panel needs.
struct RecipientTextField: NSViewRepresentable {
    @Binding var text: String
    let field: ComposeViewModel.RecipientField
    let scale: CGFloat
    let placeholder: String?
    let label: String
    /// Non-nil when the form asks this field to become first responder; the number is a
    /// request token so a repeated request is not applied twice.
    let focusRequest: Int?
    let onFocusRequestHandled: () -> Void
    let onFocusChange: (Bool) -> Void
    let onCaretChange: (Bool) -> Void
    let onTextChange: (Bool) -> Void
    let onCommand: (RecipientCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let fieldView = RecipientFieldView()
        let cell = RecipientFieldCell(textCell: "")
        fieldView.cell = cell
        fieldView.isBordered = false
        fieldView.isBezeled = false
        fieldView.drawsBackground = true
        fieldView.backgroundColor = .textBackgroundColor
        fieldView.textColor = .labelColor
        fieldView.isEditable = true
        fieldView.isSelectable = true
        fieldView.usesSingleLineMode = true
        fieldView.lineBreakMode = .byTruncatingTail
        fieldView.focusRingType = .default
        fieldView.placeholderString = placeholder
        fieldView.setAccessibilityLabel(label)
        fieldView.delegate = context.coordinator
        context.coordinator.textField = fieldView
        context.coordinator.applyAppearance(to: fieldView, scale: scale)
        return fieldView
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyAppearance(to: nsView, scale: scale)
        nsView.placeholderString = placeholder
        nsView.setAccessibilityLabel(label)

        if nsView.stringValue != text {
            if let editor = nsView.currentEditor() as? NSTextView {
                if editor.hasMarkedText() {
                    // Never overwrite an in-progress input-method composition.
                } else {
                    editor.string = text
                    editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                }
            } else {
                nsView.stringValue = text
            }
        }

        if let request = focusRequest,
           request != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = request
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView {
                    let end = (nsView.stringValue as NSString).length
                    editor.setSelectedRange(NSRange(location: end, length: 0))
                }
                onFocusRequestHandled()
            }
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.stopObservingSelection()
        coordinator.stopEscapeMonitor()
        nsView.delegate = nil
    }
}
/// The floating candidate rows. The row labels are AppKit text fields so the L2 probe
/// can read the rendered name and address without OCR or accessibility permissions.
struct RecipientSuggestionList: View {
    let suggestions: [ContactAddress]
    let highlighted: Int?
    let scale: CGFloat
    let onSelect: (Int) -> Void
    /// Called on mouse-down before the field can resign first responder. The form uses
    /// it to defer the blur clear so the click can still complete.
    let onRowPress: () -> Void

    @State private var hovered: Int?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, contact in
                    Button {
                        onSelect(index)
                    } label: {
                        row(contact, index: index)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in onRowPress() }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: contact))
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("收件人建议")
    }

    private func row(_ contact: ContactAddress, index: Int) -> some View {
        RecipientSuggestionRow(contact: contact, scale: scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(index: index))
            .contentShape(Rectangle())
            .help(contact.name.map { "\($0) <\(contact.address)>" } ?? contact.address)
            .onHover { hovering in
                hovered = hovering ? index : (hovered == index ? nil : hovered)
            }
    }

    private func rowBackground(index: Int) -> Color {
        if highlighted == index {
            return Color.accentColor.opacity(0.16)
        }
        if hovered == index {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    private func accessibilityLabel(for contact: ContactAddress) -> String {
        contact.name.map { "\($0), \(contact.address)" } ?? contact.address
    }
}

/// REQ-0023: name-first column allocation and address shortening for a candidate row.
/// Internal layout rules kept beside the field view so the AppKit carrier stays within
/// the single-file budget. Neither type is public; no behavior outside the row changes.
enum RecipientSuggestionLayout {
    static let horizontalInset: CGFloat = 8
    static let gap: CGFloat = 6
    static let preferredAddressFloor: CGFloat = 130
    static let representativeNameCharacters: CGFloat = 15

    /// Name gets its intrinsic width; the address gets at least the width needed to
    /// render `@` with one character on each side. The 130pt preferred floor is a
    /// parameter (keeps short addresses whole at 100%), not an address-width contract.
    static func widths(
        rowWidth: CGFloat,
        nameIntrinsic: CGFloat,
        hasName: Bool,
        nameFontSize: CGFloat,
        address: String,
        addressFont: NSFont
    ) -> (name: CGFloat, address: CGFloat) {
        let available = max(0, rowWidth - horizontalInset * 2)
        guard hasName, available > 0 else { return (0, available) }
        let targetNameWidth = representativeNameCharacters * nameFontSize
        let addressMinimum = ceil(textWidth(minimumAddressForm(for: address), font: addressFont))
        let addressFloor = max(
            addressMinimum,
            min(preferredAddressFloor, available - gap - targetNameWidth)
        )
        let name = min(max(0, nameIntrinsic), max(0, available - gap - addressFloor))
        return (name, max(0, available - gap - name))
    }

    /// The smallest display form we reserve room for: local head, ellipsis, `@`, domain
    /// head. Measured with the address's own first characters so a wide glyph does not
    /// silently clip the side after `@`.
    static func minimumAddressForm(for address: String) -> String {
        guard let at = address.firstIndex(of: "@"), at != address.startIndex else { return "x…@y" }
        let after = address.index(after: at)
        guard after != address.endIndex else { return "x…@y" }
        return String(address[..<at].prefix(1)) + "…@" + String(address[after...].prefix(1))
    }

    /// Middle-shortens an address while keeping `@` and at least one character on each
    /// side. The full address stays in `.help` / the accessibility label; only the
    /// rendered label text changes. Returns the input unchanged when it already fits.
    static func shortenedAddress(_ address: String, maxWidth: CGFloat, font: NSFont) -> String {
        guard textWidth(address, font: font) > maxWidth else { return address }
        guard let at = address.firstIndex(of: "@") else { return address }
        let local = address[..<at]
        let domain = address[address.index(after: at)...]
        guard !local.isEmpty, !domain.isEmpty else { return address }

        // Prefer keeping the whole domain and shortening only the local part.
        if local.count > 1 {
            for head in stride(from: local.count - 1, through: 1, by: -1) {
                let candidate = String(local.prefix(head)) + "…@" + String(domain)
                if textWidth(candidate, font: font) <= maxWidth { return candidate }
            }
        }
        // Otherwise pick the fitting candidate with the most visible characters,
        // preferring a usable domain prefix (its first label) and a local head of at
        // least two characters; a trailing domain dot is not a useful last character.
        var best: (text: String, head: Int, tail: Int, score: Int)?
        for head in 1...local.count {
            for tail in 1...domain.count {
                let candidate = String(local.prefix(head)) + "…@" + String(domain.prefix(tail))
                guard textWidth(candidate, font: font) <= maxWidth else { continue }
                let score = (head + tail) * 1_000
                    + (tail >= min(4, domain.count) ? 100 : 0)
                    + (head >= 2 ? 50 : 0)
                    + head
                    - (candidate.hasSuffix(".") ? 500 : 0)
                if best == nil || score > best!.score {
                    best = (candidate, head, tail, score)
                }
            }
        }
        if let best { return best.text }
        let minimal = String(local.prefix(1)) + "…@" + String(domain.prefix(1))
        if textWidth(minimal, font: font) <= maxWidth { return minimal }
        return String(local.prefix(1)) + "@" + String(domain.prefix(1))
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
