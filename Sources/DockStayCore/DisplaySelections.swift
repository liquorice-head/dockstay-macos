import Foundation

public struct SavedDisplayConfiguration: Identifiable {
    public let id: String
    public let displayIDs: [String]
    public let selectedID: String
    public let displayNames: [String: String]
}

@MainActor
public struct DisplaySelections {
    private static let storageKey = "displaySelections"
    private static let rememberingKey = "rememberDisplayConfigurations"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var remembersConfigurations: Bool {
        get { defaults.object(forKey: Self.rememberingKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.rememberingKey) }
    }

    public var configurations: [SavedDisplayConfiguration] {
        let stored = load()
        return stored.selections.keys.sorted().compactMap { setup in
            let ids = setup.split(separator: ",").map(String.init)
            guard let selectedID = stored.selections[setup], ids.contains(selectedID) else { return nil }
            return SavedDisplayConfiguration(id: setup, displayIDs: ids, selectedID: selectedID,
                                             displayNames: stored.names[setup] ?? [:])
        }
    }

    public func selectedID(for displays: [String: String]) -> String? {
        guard remembersConfigurations, !displays.isEmpty else { return nil }
        let setup = setupKey(for: displays)
        var stored = load()
        if let id = stored.selections[setup], displays[id] != nil {
            if stored.names[setup] != displays {
                stored.names[setup] = displays
                save(stored)
            }
            return id
        }

        // Older versions saved only the selected display. Import it when that display is connected.
        guard !stored.legacySelectionHandled, let id = legacyID, displays[id] != nil else { return nil }
        stored.selections[setup] = id
        stored.names[setup] = displays
        stored.legacySelectionHandled = true
        save(stored)
        return id
    }

    public func setSelectedID(_ id: String, for displays: [String: String]) {
        guard remembersConfigurations, displays[id] != nil else { return }
        let setup = setupKey(for: displays)
        var stored = load()
        stored.selections[setup] = id
        stored.names[setup] = displays
        save(stored)
    }

    public func removeConfiguration(_ id: String) {
        var stored = load()
        guard stored.selections.removeValue(forKey: id) != nil else { return }
        stored.names.removeValue(forKey: id)
        // Removing a setup also discards any older selection that could restore it.
        if let legacyID, id.split(separator: ",").contains(Substring(legacyID)) {
            stored.legacySelectionHandled = true
        }
        save(stored)
    }

    private struct StoredConfigurations {
        var selections: [String: String]
        var names: [String: [String: String]]
        var legacySelectionHandled: Bool
    }

    private var legacyID: String? {
        defaults.string(forKey: "selectedDisplayUUID")
    }

    private func setupKey(for displays: [String: String]) -> String {
        // Display UUIDs contain no commas. Sorting makes the key independent of display arrangement.
        displays.keys.sorted().joined(separator: ",")
    }

    private func load() -> StoredConfigurations {
        let stored = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        return StoredConfigurations(selections: stored["bySetup"] as? [String: String] ?? [:],
                                    names: stored["displayNamesBySetup"] as? [String: [String: String]] ?? [:],
                                    legacySelectionHandled: stored["legacySelectionImported"] as? Bool ?? false)
    }

    private func save(_ stored: StoredConfigurations) {
        defaults.set(["bySetup": stored.selections, "displayNamesBySetup": stored.names,
                      "legacySelectionImported": stored.legacySelectionHandled], forKey: Self.storageKey)
    }
}
