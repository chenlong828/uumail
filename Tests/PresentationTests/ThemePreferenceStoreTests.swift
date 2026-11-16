import Foundation
import Testing

@testable import Presentation

/// Each test gets its own defaults suite so the real `appearance.theme` preference
/// is never read or written. The suite is removed again when the test finishes.
private func makeDefaults() -> (defaults: UserDefaults, name: String) {
    let name = "uumail.tests.theme.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

@Suite("ThemePreferenceStore")
struct ThemePreferenceStoreTests {
    @Test("T-SCN-0011-01: an absent preference means follow the system")
    func defaultsToSystemWhenUnset() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ThemePreferenceStore(defaults: defaults)

        #expect(store.load() == .system)
    }

    @Test("each of the three choices round-trips through the store")
    func roundTripsEachPreference() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ThemePreferenceStore(defaults: defaults)
        for preference in ThemePreference.allCases {
            store.save(preference)
            #expect(store.load() == preference)
        }
    }

    @Test("T-SCN-0011-04: a corrupt or unknown value falls back to the system")
    func invalidValueFallsBackToSystem() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ThemePreferenceStore(defaults: defaults)
        for raw in ["purple", "", "Dark", "dark-mode"] {
            defaults.set(raw, forKey: ThemePreferenceStore.defaultsKey)
            #expect(store.load() == .system)
        }

        // Saving the fallback must clean the corrupt raw value instead of treating
        // the already-loaded `.system` as a no-op.
        defaults.set("purple", forKey: ThemePreferenceStore.defaultsKey)
        store.save(.system)
        #expect(defaults.string(forKey: ThemePreferenceStore.defaultsKey) == "system")
    }

    @Test("T-SCN-0011-02: a value written by one store is restored by the next")
    func persistsAndRestoresAcrossInstances() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        ThemePreferenceStore(defaults: defaults).save(.dark)

        // A second instance models the next launch reading the same suite.
        #expect(ThemePreferenceStore(defaults: defaults).load() == .dark)
    }

    @Test("saving the same value twice keeps one value and does not throw")
    func repeatedSaveKeepsSingleValue() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ThemePreferenceStore(defaults: defaults)
        store.save(.light)
        store.save(.light)

        #expect(defaults.string(forKey: ThemePreferenceStore.defaultsKey) == "light")
        #expect(store.load() == .light)
    }
}
