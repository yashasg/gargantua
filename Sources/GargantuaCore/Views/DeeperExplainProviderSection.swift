import SwiftUI

/// Picks which provider powers an on-demand "Explain deeper" request. Inline
/// explanations always run locally; this only routes the escalation — Cloud
/// (metered API key) or Claude Code (your subscription, no key). Sits at the
/// top of the "Deeper explanations" job group in the AI settings tab.
struct DeeperExplainProviderSection: View {
    @AppStorage(DeeperExplainProvider.userDefaultsKey)
    private var providerRawValue = DeeperExplainProvider.cloud.rawValue

    private var provider: DeeperExplainProvider {
        DeeperExplainProvider(rawValue: providerRawValue) ?? .cloud
    }

    var body: some View {
        SettingsSectionContainer(
            "Explain-deeper provider",
            subtitle: "When you tap “Explain deeper” on a scan result, route it through this provider."
        ) {
            GargantuaSegmentedPicker(
                selection: Binding(
                    get: { provider },
                    set: { providerRawValue = $0.rawValue }
                ),
                options: DeeperExplainProvider.allCases.map { (value: $0, label: $0.label) },
                accessibilityLabel: "Deeper explanation provider"
            )

            HStack(alignment: .top, spacing: GargantuaSpacing.space2) {
                SettingsRowIcon(
                    systemName: provider == .cloud ? "cloud" : "terminal",
                    size: 14
                )
                Text(provider.settingsDescription)
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}
