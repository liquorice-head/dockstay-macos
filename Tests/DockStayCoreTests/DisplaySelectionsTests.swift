import Foundation
import Testing
@testable import DockStayCore

@MainActor
struct DisplaySelectionsTests {
    private let home = ["laptop": "Built-in Display", "home": "Home Monitor"]
    private let work = ["laptop": "Built-in Display", "work": "Work Monitor"]

    @Test func restoresIndependentSelectionsForTheSameLaptop() throws {
        try withDefaults { defaults in
            let selections = DisplaySelections(defaults: defaults)
            selections.setSelectedID("home", for: home)
            #expect(selections.selectedID(for: work) == nil)
            selections.setSelectedID("laptop", for: work)

            let reopened = DisplaySelections(defaults: defaults)
            #expect(reopened.selectedID(for: ["laptop": "Built-in Display"]) == nil)
            #expect(reopened.selectedID(for: [:]) == nil)
            #expect(reopened.selectedID(for: home) == "home")
            #expect(reopened.selectedID(for: work) == "laptop")

            reopened.setSelectedID("work", for: work)
            reopened.setSelectedID("home", for: work)
            #expect(reopened.selectedID(for: work) == "work")
            #expect(reopened.selectedID(for: home) == "home")
        }
    }

    @Test func importsLegacyChoiceOnceItsDisplayReturns() throws {
        try withDefaults { defaults in
            defaults.set("home", forKey: "selectedDisplayUUID")
            let selections = DisplaySelections(defaults: defaults)
            #expect(selections.selectedID(for: work) == nil)
            selections.setSelectedID("work", for: work)

            #expect(selections.selectedID(for: home) == "home")
            selections.setSelectedID("laptop", for: home)

            let reopened = DisplaySelections(defaults: defaults)
            #expect(reopened.selectedID(for: ["home": "Home Monitor"]) == nil)
            #expect(reopened.selectedID(for: home) == "laptop")
            #expect(reopened.selectedID(for: work) == "work")
        }
    }

    @Test func disablingRememberingPreservesEntriesWithoutSavingOrRestoring() throws {
        try withDefaults { defaults in
            let selections = DisplaySelections(defaults: defaults)
            #expect(selections.remembersConfigurations)
            selections.setSelectedID("home", for: home)
            selections.remembersConfigurations = false
            selections.setSelectedID("laptop", for: home)
            selections.setSelectedID("work", for: work)

            let reopened = DisplaySelections(defaults: defaults)
            #expect(!reopened.remembersConfigurations)
            #expect(reopened.selectedID(for: home) == nil)
            #expect(reopened.configurations.map(\.selectedID) == ["home"])

            reopened.remembersConfigurations = true
            #expect(reopened.selectedID(for: home) == "home")
            #expect(reopened.selectedID(for: work) == nil)
        }
    }

    @Test func removesOneConfigurationEvenWhenRememberingIsOff() throws {
        try withDefaults { defaults in
            let selections = DisplaySelections(defaults: defaults)
            selections.setSelectedID("home", for: home)
            selections.setSelectedID("work", for: work)
            let homeConfiguration = try #require(selections.configurations.first { $0.selectedID == "home" })
            #expect(homeConfiguration.displayNames == home)
            selections.remembersConfigurations = false
            selections.removeConfiguration(homeConfiguration.id)

            let reopened = DisplaySelections(defaults: defaults)
            #expect(reopened.configurations.map(\.selectedID) == ["work"])
            reopened.remembersConfigurations = true
            #expect(reopened.selectedID(for: home) == nil)
            #expect(reopened.selectedID(for: work) == "work")
        }
    }

    @Test func namesPreviouslySavedDisplaysAndDoesNotRestoreADeletedLegacyChoice() throws {
        try withDefaults { defaults in
            defaults.set("home", forKey: "selectedDisplayUUID")
            defaults.set(["bySetup": ["home,laptop": "home"]], forKey: "displaySelections")
            let selections = DisplaySelections(defaults: defaults)
            #expect(selections.configurations.first?.displayNames == [:])
            #expect(selections.selectedID(for: home) == "home")
            #expect(selections.configurations.first?.displayNames == home)

            selections.removeConfiguration("home,laptop")
            #expect(selections.configurations.isEmpty)
            #expect(selections.selectedID(for: home) == nil)
        }
    }

    private func withDefaults(_ run: (UserDefaults) throws -> Void) throws {
        let suite = "DockStay.DisplaySelectionsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(defaults)
    }
}
