import Foundation

/// User-visible appearance choice. The raw values are the on-disk representation;
/// keep them stable so a preference written by an older build still loads.
public enum ThemePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Local UI-preference adapter for the application theme.
///
/// The store is deliberately small: it reads one key, falls back to `.system` for
/// anything it does not recognise, and writes the same key back. It is not the
/// session source of truth — `UumailApp` owns the live value in `@State`; this type
/// only mirrors the preference across launches.
public struct ThemePreferenceStore {
    static let defaultsKey = "appearance.theme"

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
    /// therefore means "follow the system"; the caller never has to handle `nil`.
    public func load() -> ThemePreference {
        guard let raw = defaults.string(forKey: Self.defaultsKey),
              let preference = ThemePreference(rawValue: raw) else {
            return .system
        }
        return preference
    }

    /// Writes at most one key. There is no synchronous failure signal from
    /// `UserDefaults`, so this never throws and never rolls back the caller's
    /// session state; a failed write only surfaces as an old value on next launch.
    public func save(_ preference: ThemePreference) {
        let raw = preference.rawValue
        guard defaults.string(forKey: Self.defaultsKey) != raw else { return }
        defaults.set(raw, forKey: Self.defaultsKey)
    }
}
