import Foundation
import Testing
@testable import GargantuaCore

@Suite("DeeperExplainProvider")
struct DeeperExplainProviderTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "deeper-explain-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Defaults to Cloud when nothing is stored")
    func defaultsToCloud() throws {
        let defaults = try makeDefaults()
        #expect(DeeperExplainProvider.stored(in: defaults) == .cloud)
    }

    @Test("store/stored round-trips each provider")
    func roundTrips() throws {
        let defaults = try makeDefaults()
        for provider in DeeperExplainProvider.allCases {
            provider.store(in: defaults)
            #expect(DeeperExplainProvider.stored(in: defaults) == provider)
        }
    }

    @Test("Unknown stored value falls back to Cloud")
    func unknownFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set("not-a-provider", forKey: DeeperExplainProvider.userDefaultsKey)
        #expect(DeeperExplainProvider.stored(in: defaults) == .cloud)
    }

    @Test("Every provider has a non-empty label and description")
    func copyIsPresent() {
        for provider in DeeperExplainProvider.allCases {
            #expect(!provider.label.isEmpty)
            #expect(!provider.settingsDescription.isEmpty)
        }
    }
}
