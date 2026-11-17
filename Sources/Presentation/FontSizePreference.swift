import Foundation

/// User-visible font-size choice. The raw value is the stable integer percentage;
/// keep it stable so a preference written by an older build still loads.
public enum FontSizePreference: Int, CaseIterable, Sendable {
    case percent100 = 100
    case percent120 = 120
    case percent145 = 145
    case percent175 = 175
    case percent225 = 225

    /// The render factor: 1.0 for the identity level, 1.2 … 2.25 for the rest.
    public var scale: Double { Double(rawValue) / 100 }

    /// Display string used by the menu. No localisation dependency.
    public var title: String { "\(rawValue)%" }
}

/// Local UI-preference adapter for the application font size.
///
/// Like `ThemePreferenceStore`, the store is deliberately small: it reads one key,
/// falls back to `.percent100` for anything it does not recognise, and writes the
/// same key back. It is not the session source of truth — `UumailApp` owns the live
/// value in `@State`; this type only mirrors the preference across launches.
public struct FontSizePreferenceStore {
    static let defaultsKey = "appearance.fontSize"

    private let defaults: UserDefaults

    /// Production entry point: writes to `UserDefaults.standard`.
    public init() {
        defaults = .standard
    }

    /// Test seam: inject an isolated suite instead of touching the real preference.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Any missing, unreadable, or unknown value is an invalid preference and
    /// therefore means 100%; the caller never has to handle `nil`.
    ///
    /// The on-disk form is the string raw value. `UserDefaults` bridges a legal
    /// integer (for example an integer `175`) to its string form, which is accepted
    /// as the same level; fractional, out-of-range, empty, or non-numeric values
    /// all fall back to 100%.
    public func load() -> FontSizePreference {
        guard let raw = defaults.string(forKey: Self.defaultsKey),
              let percent = Int(raw),
              let preference = FontSizePreference(rawValue: percent)
        else {
            return .percent100
        }
        return preference
    }

    /// Writes at most one key. There is no synchronous failure signal from
    /// `UserDefaults`, so this never throws and never rolls back the caller's
    /// session state; a failed write only surfaces as an old value on next launch.
    public func save(_ preference: FontSizePreference) {
        let raw = String(preference.rawValue)
        guard defaults.string(forKey: Self.defaultsKey) != raw else { return }
        defaults.set(raw, forKey: Self.defaultsKey)
    }
}
