import Presentation
import SwiftUI

/// The `View` menu's font-size submenu. It mirrors `ThemeCommands`: the picker maps
/// the five user-visible choices to the app's state and the preference store, and it
/// writes nothing except the local UI preference.
struct FontSizeCommands: Commands {
    @Binding var fontSize: FontSizePreference
    let store: FontSizePreferenceStore

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("字体大小", selection: selection) {
                ForEach(FontSizePreference.allCases, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
        }
    }

    /// Selecting the current item is a no-op: no state change, no second write, no
    /// flicker. A real change updates the session first and then mirrors it to disk.
    private var selection: Binding<FontSizePreference> {
        Binding(
            get: { fontSize },
            set: { newValue in
                guard newValue != fontSize else { return }
                fontSize = newValue
                store.save(newValue)
            }
        )
    }
}
