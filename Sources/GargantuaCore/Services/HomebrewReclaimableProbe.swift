import Foundation

/// Computes the total on-demand Homebrew reclaimable space — cache + old
/// versions (`brew cleanup -n`) plus orphan formulae (`brew autoremove -n`) —
/// so the dashboard can surface it as a discoverability signpost that
/// deep-links into the Developer Tools › Homebrew card (gargantua-zdyj).
///
/// Reuses the existing read-only ``DeveloperToolPreviewAdapter`` dry-runs:
/// no new scanner, and nothing is ever executed. These ops stay out of Deep
/// Clean (re-download cost), so this is a signpost only.
public enum HomebrewReclaimableProbe {
    /// Sum of a Homebrew preview's cleanup reclaimable (cache + old versions)
    /// and its orphan-formula Cellar sizes, saturating at `Int64.max` rather
    /// than trapping — the value is only ever shown as a display string.
    public static func totalBytes(for preview: DeveloperToolPreview) -> Int64 {
        let cleanup = preview.reclaimableBytes
        let orphans = preview.homebrewAutoremove?.totalBytes ?? 0
        let (sum, overflow) = cleanup.addingReportingOverflow(orphans)
        return overflow ? .max : sum
    }

    /// Probes Homebrew with read-only dry-runs. Returns the total reclaimable
    /// bytes (may be `0`), or `nil` when Homebrew isn't installed or the
    /// preview fails — callers hide the signpost on `nil`. Blocking (shells out
    /// to `brew`); call off the main actor.
    public static func probe(
        adapter: DeveloperToolPreviewAdapter = DeveloperToolPreviewAdapter()
    ) -> Int64? {
        guard adapter.availability(for: .homebrew).isInstalled,
              let preview = try? adapter.preview(.homebrew) else { return nil }
        return totalBytes(for: preview)
    }
}
