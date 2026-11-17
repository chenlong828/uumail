import Foundation
import Testing

@testable import Presentation

/// Each test gets its own defaults suite so the real `appearance.fontSize` preference
/// is never read or written. The suite is removed again when the test finishes.
private func makeDefaults() -> (defaults: UserDefaults, name: String) {
    let name = "uumail.tests.font-size.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

@Suite("FontSizePreferenceStore")
struct FontSizePreferenceStoreTests {
    @Test("T-SCN-0015-01: an absent preference means 100%")
    func defaultsTo100WhenUnset() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = FontSizePreferenceStore(defaults: defaults)

        #expect(store.load() == .percent100)
    }

    @Test("T-SCN-0015-02: each of the five levels round-trips through the store")
    func roundTripsEachLevel() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = FontSizePreferenceStore(defaults: defaults)
        for preference in FontSizePreference.allCases {
            store.save(preference)
            #expect(store.load() == preference)
        }
    }

    @Test("T-SCN-0015-03: a value written by one store is restored by the next")
    func persistsAndRestoresAcrossInstances() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        FontSizePreferenceStore(defaults: defaults).save(.percent175)

        // A second instance models the next launch reading the same suite.
        #expect(FontSizePreferenceStore(defaults: defaults).load() == .percent175)
    }

    @Test("T-SCN-0015-04: a corrupt or unknown value falls back to 100%")
    func invalidValueFallsBackTo100() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = FontSizePreferenceStore(defaults: defaults)
        for raw in ["purple", "", "0", "250", "175.5"] {
            defaults.set(raw, forKey: FontSizePreferenceStore.defaultsKey)
            #expect(store.load() == .percent100)
        }

        // A non-string payload is also an invalid preference.
        defaults.set(999, forKey: FontSizePreferenceStore.defaultsKey)
        #expect(store.load() == .percent100)

        // Saving the fallback must clean an invalid raw value instead of treating
        // the already-loaded `.percent100` as a no-op.
        defaults.set("purple", forKey: FontSizePreferenceStore.defaultsKey)
        store.save(.percent100)
        #expect(defaults.string(forKey: FontSizePreferenceStore.defaultsKey) == "100")
    }

    @Test("a valid integer is accepted as the same level (UserDefaults bridging)")
    func validIntegerIsAcceptedAsSameLevel() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(175, forKey: FontSizePreferenceStore.defaultsKey)

        #expect(FontSizePreferenceStore(defaults: defaults).load() == .percent175)
    }

    @Test("saving the same value twice keeps one value and does not throw")
    func repeatedSaveKeepsSingleValue() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = FontSizePreferenceStore(defaults: defaults)
        store.save(.percent225)
        store.save(.percent225)

        #expect(defaults.string(forKey: FontSizePreferenceStore.defaultsKey) == "225")
        #expect(store.load() == .percent225)
    }
}
