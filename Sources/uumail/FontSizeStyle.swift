import AppKit
import Presentation
import SwiftUI

/// The app-wide font-size preference, injected once by `UumailApp`. It defaults to
/// 100% so a view hosted without the root environment stays at the original size.
private struct FontSizePreferenceKey: EnvironmentKey {
    static let defaultValue: FontSizePreference = .percent100
}

extension EnvironmentValues {
    var fontSizePreference: FontSizePreference {
        get { self[FontSizePreferenceKey.self] }
        set { self[FontSizePreferenceKey.self] = newValue }
    }
}

extension FontSizePreference {
    /// `CGFloat` form used by layout values such as the header's label column.
    var scaleFactor: CGFloat { CGFloat(rawValue) / 100 }

    /// 100% returns the exact semantic font the view used before this feature, so the
    /// baseline cannot drift. Other levels scale the AppKit text style's point size
    /// through its font descriptor, which keeps the family and weight.
    func font(for style: Font.TextStyle) -> Font {
        guard self != .percent100 else { return Self.semantic(style) }
        let base = NSFont.preferredFont(forTextStyle: Self.appKit(style))
        guard let scaled = NSFont(descriptor: base.fontDescriptor, size: base.pointSize * scaleFactor) else {
            return Self.semantic(style)
        }
        return Font(scaled)
    }

    private static func semantic(_ style: Font.TextStyle) -> Font {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        @unknown default: .body
        }
    }

    private static func appKit(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}

private struct ScaledFontModifier: ViewModifier {
    let style: Font.TextStyle
    @Environment(\.fontSizePreference) private var preference

    func body(content: Content) -> some View {
        content.font(preference.font(for: style))
    }
}

/// For text that inherits the *default* font in the production source. Applying
/// `.font(.body)` at 100% changes its line height (32.0pt -> 31.5pt for a two-line
/// row), so 100% must apply no modifier at all; above 100% the scaled font is
/// applied explicitly.
private struct ScaledInheritedFontModifier: ViewModifier {
    let style: Font.TextStyle
    @Environment(\.fontSizePreference) private var preference

    func body(content: Content) -> some View {
        if preference == .percent100 {
            content
        } else {
            content.font(preference.font(for: style))
        }
    }
}

extension View {
    /// For sites that already set `.font(style)`: 100% applies exactly that semantic font.
    func scaledFont(_ style: Font.TextStyle) -> some View {
        modifier(ScaledFontModifier(style: style))
    }

    /// For sites that inherit the default font today: 100% applies nothing (exact
    /// baseline), above 100% applies the scaled style.
    func scaledInheritedFont(_ style: Font.TextStyle) -> some View {
        modifier(ScaledInheritedFontModifier(style: style))
    }
}
