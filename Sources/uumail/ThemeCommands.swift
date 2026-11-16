import Presentation
import SwiftUI

/// The `View` menu's theme submenu. This only maps the three user-visible choices
/// to the app's state and the preference store; it does not read mail or write
/// anything except the local UI preference.
struct ThemeCommands: Commands {
    @Binding var theme: ThemePreference
    let store: ThemePreferenceStore

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("主题", selection: selection) {
                Text("跟随系统").tag(ThemePreference.system)
                Text("浅色").tag(ThemePreference.light)
                Text("深色").tag(ThemePreference.dark)
            }
        }
    }

    /// Selecting the current item is a no-op: no state change, no second write, no
    /// flicker. A real change updates the session first and then mirrors it to disk.
    private var selection: Binding<ThemePreference> {
        Binding(
            get: { theme },
            set: { newValue in
                guard newValue != theme else { return }
                theme = newValue
                store.save(newValue)
            }
        )
    }
}

extension ThemePreference {
    /// `nil` leaves the appearance to the system; the forced values pin every
    /// window and sheet presented by this app.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
