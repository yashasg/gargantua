import Foundation
import Testing
@testable import GargantuaCore

@Suite("DeveloperToolPanel autoremove suffix")
struct DeveloperToolPanelOperationsTests {
    private func homebrewPreview(orphans: Int) -> DeveloperToolPreview {
        let formulae = (0..<orphans).map { i in
            DeveloperToolPreviewItem(
                id: "homebrew-autoremove-\(i)", tool: .homebrew, title: "f\(i)",
                reclaimableBytes: 10, commandPreview: ["brew", "autoremove"])
        }
        return DeveloperToolPreview(
            tool: .homebrew, commandPreview: ["brew", "cleanup", "-n"], items: [], rawOutput: "",
            homebrewAutoremove: HomebrewAutoremovePreview(formulae: formulae))
    }

    @Test("Shows the orphan count for autoremove with >=1 formula")
    func showsCount() {
        #expect(DeveloperToolPanel.autoremoveFormulaSuffix(.homebrewAutoremove, preview: homebrewPreview(orphans: 3)) == " · 3 formulae")
        #expect(DeveloperToolPanel.autoremoveFormulaSuffix(.homebrewAutoremove, preview: homebrewPreview(orphans: 1)) == " · 1 formula")
    }

    @Test("No suffix for other operations or zero orphans")
    func noSuffixOtherwise() {
        #expect(DeveloperToolPanel.autoremoveFormulaSuffix(.homebrewCleanup, preview: homebrewPreview(orphans: 3)) == "")
        #expect(DeveloperToolPanel.autoremoveFormulaSuffix(.homebrewAutoremove, preview: homebrewPreview(orphans: 0)) == "")
    }
}
