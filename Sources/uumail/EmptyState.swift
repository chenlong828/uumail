import Presentation
import SwiftUI

/// Scaling-aware replacement for the framework empty states. `ContentUnavailableView`
/// and a string-titled `Button` do not respond to an environment font, so at 100% this
/// view renders the exact original framework shape and above 100% it draws the same
/// content with explicitly scaled fonts and a scaled icon.
///
/// The 100% -> 120% switch changes this placeholder subtree from the framework view to
/// the custom view. The subtree owns no user state (no selection, scroll, search or
/// draft), so the switch cannot reset any of them; this is the explicit exception
/// recorded in SCN-0015 / design.md §5.2.
struct EmptyState: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var descriptionStyle: Font.TextStyle = .body
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isSelectable: Bool = false

    @Environment(\.fontSizePreference) private var preference

    var body: some View {
        if isSelectable {
            content.textSelection(.enabled)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if preference == .percent100 {
            legacy
        } else {
            scaled
        }
    }

    @ViewBuilder
    private var legacy: some View {
        if let actionTitle, let action {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description {
                    legacyDescriptionText(description)
                }
            } actions: {
                Button(actionTitle, action: action)
            }
        } else if let description {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: legacyDescriptionText(description)
            )
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }

    /// A default (`body`) description gets no `.font` modifier at all; an explicit
    /// caption keeps `.font(.caption)`.
    private func legacyDescriptionText(_ text: String) -> Text {
        if let font = legacyDescriptionFont {
            return Text(text).font(font)
        }
        return Text(text)
    }

    /// 100% must keep the exact production font: `.font(.body)` shifts wrapped line
    /// height 32.0 -> 31.5pt, so body returns nil and applies no modifier.
    private var legacyDescriptionFont: Font? {
        switch descriptionStyle {
        case .body: nil
        default: FontSizePreference.percent100.font(for: descriptionStyle)
        }
    }

    private var scaled: some View {
        VStack(spacing: 10 * preference.scaleFactor) {
            Image(systemName: systemImage)
                .font(.system(size: 52 * preference.scaleFactor))
                .foregroundStyle(.secondary)
            Text(title)
                // `ContentUnavailableView`'s title measures 26pt on this platform.
                // Scaling `.title2` (17pt) would make the 120% title smaller than the
                // 100% baseline, so the custom branch scales the measured 26pt base.
                .font(.system(size: 26 * preference.scaleFactor, weight: .semibold))
                .multilineTextAlignment(.center)
            if let description {
                Text(description)
                    .font(preference.font(for: descriptionStyle))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(preference.font(for: .body))
                }
                .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
