import MailDomain
import Presentation
import SwiftUI

/// Frames of the two address fields in the form's coordinate space, collected through a
/// fixed-height `GeometryReader` so the suggestion panel can be anchored under the
/// focused field without joining the Form's layout.
struct RecipientFieldFrames: Equatable {
    var to: CGRect = .zero
    var cc: CGRect = .zero
}

struct RecipientFieldFrameKey: PreferenceKey {
    static var defaultValue: RecipientFieldFrames { RecipientFieldFrames() }

    static func reduce(value: inout RecipientFieldFrames, nextValue: () -> RecipientFieldFrames) {
        let next = nextValue()
        if next.to != .zero { value.to = next.to }
        if next.cc != .zero { value.cc = next.cc }
    }
}

/// The compose form's address rows plus the candidate overlay. Kept in its own file so
/// the L2 probe can compile just this view and `RecipientTextField.swift` without
/// pulling the editor/format-bar/WebKit tree.
struct ComposeRecipientForm<Content: View>: View {
    @Bindable var viewModel: ComposeViewModel
    let scale: CGFloat
    let sheetHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var focusedField: ComposeViewModel.RecipientField?
    @State private var frames = RecipientFieldFrames()
    @State private var suggestionClickInFlight = false
    @State private var blurToken = 0
    @State private var focusToken = 0
    @State private var focusTarget: ComposeViewModel.RecipientField?

    var body: some View {
        Form {
            LabeledContent("收件人") {
                GeometryReader { proxy in
                    RecipientTextField(
                        text: $viewModel.to,
                        field: .to,
                        scale: scale,
                        placeholder: "a@example.com",
                        label: "收件人",
                        focusRequest: focusTarget == .to ? focusToken : nil,
                        onFocusRequestHandled: { focusTarget = nil },
                        onFocusChange: { handleFocus(.to, focused: $0) },
                        onCaretChange: { atEnd in
                            guard focusedField == .to else { return }
                            viewModel.recipientCaretChanged(atEnd: atEnd)
                        },
                        onTextChange: { atEnd in
                            guard focusedField == .to else { return }
                            viewModel.recipientTextChanged(in: .to, caretAtEnd: atEnd)
                        },
                        onCommand: { handleCommand($0, in: .to) }
                    )
                    .preference(
                        key: RecipientFieldFrameKey.self,
                        value: RecipientFieldFrames(
                            to: proxy.frame(in: .global),
                            cc: .zero
                        )
                    )
                }
                .frame(height: 24 * max(scale, 0.5))
            }
            LabeledContent("抄送") {
                GeometryReader { proxy in
                    RecipientTextField(
                        text: $viewModel.cc,
                        field: .cc,
                        scale: scale,
                        placeholder: nil,
                        label: "抄送",
                        focusRequest: focusTarget == .cc ? focusToken : nil,
                        onFocusRequestHandled: { focusTarget = nil },
                        onFocusChange: { handleFocus(.cc, focused: $0) },
                        onCaretChange: { atEnd in
                            guard focusedField == .cc else { return }
                            viewModel.recipientCaretChanged(atEnd: atEnd)
                        },
                        onTextChange: { atEnd in
                            guard focusedField == .cc else { return }
                            viewModel.recipientTextChanged(in: .cc, caretAtEnd: atEnd)
                        },
                        onCommand: { handleCommand($0, in: .cc) }
                    )
                    .preference(
                        key: RecipientFieldFrameKey.self,
                        value: RecipientFieldFrames(
                            to: .zero,
                            cc: proxy.frame(in: .global)
                        )
                    )
                }
                .frame(height: 24 * max(scale, 0.5))
            }
            content()
        }
        .padding(12)
        .onPreferenceChange(RecipientFieldFrameKey.self) { frames = $0 }
        .overlay(alignment: .topLeading) {
            if let field = focusedField,
               let globalRect = frame(for: field),
               !viewModel.recipientSuggestions.isEmpty {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    let rect = CGRect(
                        x: globalRect.minX - origin.x,
                        y: globalRect.minY - origin.y,
                        width: globalRect.width,
                        height: globalRect.height
                    )
                    let size = panelSize(anchor: rect)
                    RecipientSuggestionList(
                        suggestions: viewModel.recipientSuggestions,
                        highlighted: viewModel.highlightedSuggestion,
                        scale: scale,
                        onSelect: { select($0, in: field) },
                        onRowPress: { suggestionClickInFlight = true }
                    )
                    .frame(width: size.width, height: size.height)
                    .offset(x: rect.minX, y: rect.maxY + 4)
                }
            }
        }
    }

    private func frame(for field: ComposeViewModel.RecipientField) -> CGRect? {
        let rect = field == .to ? frames.to : frames.cc
        guard rect != .zero,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite
        else { return nil }
        return rect
    }

    private func panelSize(anchor: CGRect) -> CGSize {
        let factor = max(scale, 0.5)
        let rowHeight = 24 * factor
        let contentHeight = CGFloat(viewModel.recipientSuggestions.count) * rowHeight + 8
        let cap = 240 * factor
        // The form starts below the sheet header + divider; 80 is a conservative
        // allowance for that chrome and the form's own top padding.
        let availableBelow = max(0, sheetHeight - 80 - anchor.maxY - 8)
        let height = max(
            min(contentHeight, cap, availableBelow),
            min(contentHeight, rowHeight + 8)
        )
        return CGSize(width: max(anchor.width, 200), height: height)
    }

    private func handleFocus(_ field: ComposeViewModel.RecipientField, focused: Bool) {
        if focused {
            blurToken += 1
            suggestionClickInFlight = false
            focusedField = field
            viewModel.recipientFocusChanged(in: field)
            return
        }

        guard focusedField == field else { return }
        guard suggestionClickInFlight else {
            focusedField = nil
            viewModel.recipientFocusLost()
            return
        }

        // A candidate click resigns the field before the button action runs. Defer the
        // clear to the next runloop so the click can still select; re-focus invalidates
        // the pending clear via `blurToken`.
        blurToken += 1
        let token = blurToken
        DispatchQueue.main.async {
            guard blurToken == token else { return }
            suggestionClickInFlight = false
            if focusedField == field {
                focusedField = nil
                viewModel.recipientFocusLost()
            }
        }
    }

    private func select(_ index: Int, in field: ComposeViewModel.RecipientField) {
        suggestionClickInFlight = false
        guard viewModel.selectRecipientSuggestion(at: index) else { return }
        focusedField = field
        focusTarget = field
        focusToken += 1
    }

    private func handleCommand(_ command: RecipientCommand, in field: ComposeViewModel.RecipientField) -> Bool {
        switch command {
        case .moveUp:
            guard !viewModel.recipientSuggestions.isEmpty else { return false }
            viewModel.moveRecipientHighlight(by: -1)
            return true
        case .moveDown:
            guard !viewModel.recipientSuggestions.isEmpty else { return false }
            viewModel.moveRecipientHighlight(by: 1)
            return true
        case .commit:
            let selected = viewModel.selectHighlightedRecipientSuggestion()
            if selected {
                focusTarget = field
                focusToken += 1
            }
            return selected
        case .dismiss:
            let hadSuggestions = !viewModel.recipientSuggestions.isEmpty
            viewModel.dismissRecipientSuggestions()
            return hadSuggestions
        }
    }
}
