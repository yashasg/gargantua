import SwiftUI

/// Informational dashboard signpost for on-demand Homebrew reclaimable space
/// (gargantua-zdyj). Homebrew cleanup (cache + old versions + orphan formulae)
/// lives two clicks deep in Developer Tools and never runs as part of Deep
/// Clean, so a user who doesn't open that tab never learns there's space to
/// reclaim. This bubbles the total up and deep-links into the Homebrew card —
/// it does not run anything.
struct DashboardHomebrewSignpost: View {
    let reclaimableBytes: Int64
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: GargantuaSpacing.space3) {
                DeveloperToolLogoBadge(tool: .homebrew, size: 24)

                VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
                    Text("Homebrew has \(AlertItem.formatBytes(reclaimableBytes)) to reclaim")
                        .font(GargantuaFonts.label)
                        .foregroundStyle(GargantuaColors.ink)

                    Text("Cache, old versions, and orphan formulae. Runs on demand in Developer Tools — not part of Deep Clean.")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: GargantuaSpacing.space3)

                HStack(spacing: GargantuaSpacing.space1) {
                    Text("Open")
                        .font(GargantuaFonts.label)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(GargantuaColors.accent)
            }
            .padding(GargantuaSpacing.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GargantuaColors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: GargantuaRadius.medium)
                    .stroke(GargantuaColors.borderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.medium))
        }
        .buttonStyle(.plain)
        .help("Open Developer Tools to review and run Homebrew cleanup on demand")
        .accessibilityLabel("Homebrew has \(AlertItem.formatBytes(reclaimableBytes)) reclaimable. Opens Developer Tools.")
    }
}
