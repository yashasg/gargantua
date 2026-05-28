import AppKit
import GargantuaLicensing
import SwiftUI

/// Settings → License pane. Displays current license / trial state and accepts a
/// FastSpring-issued `.gargantualicense` plist via file picker or pasted XML.
/// Placeholder URLs are swapped to production values in Phase 5.
struct LicenseSettingsSection: View {
    @State private var model = LicenseStateModel.shared
    @State private var pastedPlist: String = ""
    @State private var inlineFeedback: InlineFeedback?

    private let store: LicenseStore

    init(store: LicenseStore = LicenseStore()) {
        self.store = store
    }

    private enum InlineFeedback: Equatable {
        case success(String)
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space5) {
            statusCard
            activationCard
        }
        .task { await model.refresh() }
    }

    // MARK: Status card

    private var statusCard: some View {
        SettingsSectionContainer("License", subtitle: statusSubtitle) {
            HStack(spacing: GargantuaSpacing.space3) {
                SettingsRowIcon(systemName: statusIconName, size: 16)

                VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
                    Text(statusHeadline)
                        .font(GargantuaFonts.label)
                        .foregroundStyle(GargantuaColors.ink)

                    if let detail = statusDetail {
                        Text(detail)
                            .font(GargantuaFonts.caption)
                            .foregroundStyle(GargantuaColors.ink3)
                    }
                }

                Spacer()

                if case .licensed = model.state {
                    GargantuaButton("Deactivate", icon: "minus.circle", tone: .neutral) {
                        try? store.clear()
                        Task { await model.refresh() }
                    }
                }
            }
            .padding(.vertical, GargantuaSpacing.space1)
        }
    }

    // MARK: Activation card

    @ViewBuilder
    private var activationCard: some View {
        if case .licensed = model.state {
            EmptyView()
        } else {
            SettingsSectionContainer(
                "Activate",
                subtitle: "Open the .gargantualicense file from your purchase email."
            ) {
                VStack(alignment: .leading, spacing: GargantuaSpacing.space3) {
                    HStack(spacing: GargantuaSpacing.space3) {
                        Spacer()
                        GargantuaButton("Open store", icon: "arrow.up.right.square", tone: .neutral) {
                            openBuyURL()
                        }
                        GargantuaButton("Open license file…", icon: "doc.badge.plus", tone: .primary) {
                            pickAndActivate()
                        }
                    }

                    DisclosureGroup("Paste license XML instead") {
                        VStack(alignment: .leading, spacing: GargantuaSpacing.space3) {
                            TextField(
                                "Paste the contents of your .gargantualicense file",
                                text: $pastedPlist,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(GargantuaFonts.monoPath)
                            .lineLimit(4 ... 10)

                            HStack {
                                Spacer()
                                GargantuaButton(
                                    "Activate",
                                    icon: "key.fill",
                                    tone: .primary,
                                    isDisabled: pastedPlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ) {
                                    activateFromPastedXML()
                                }
                            }
                        }
                        .padding(.top, GargantuaSpacing.space2)
                    }
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink2)

                    if let inlineFeedback {
                        feedbackRow(inlineFeedback)
                    }
                }
            }
        }
    }

    private func feedbackRow(_ feedback: InlineFeedback) -> some View {
        let color: Color = switch feedback {
        case .success: GargantuaColors.safe
        case .error: GargantuaColors.protected_
        }
        let icon: String = switch feedback {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
        let text: String = switch feedback {
        case .success(let message): message
        case .error(let message): message
        }
        return HStack(spacing: GargantuaSpacing.space2) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(GargantuaFonts.caption)
                .foregroundStyle(color)
        }
    }

    private func pickAndActivate() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.allowedFileTypes = ["gargantualicense", "plist", "xml"]
        panel.prompt = "Activate"
        panel.title = "Open Gargantua license file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let receipt = try store.save(fileURL: url)
            inlineFeedback = .success("Activated for \(receipt.email ?? receipt.name ?? "this license").")
            pastedPlist = ""
            Task { await model.refresh() }
        } catch {
            inlineFeedback = .error(activationErrorMessage(for: error))
        }
    }

    private func activateFromPastedXML() {
        let trimmed = pastedPlist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            inlineFeedback = .error("Couldn't read the pasted text.")
            return
        }
        do {
            let receipt = try store.save(plistData: data)
            inlineFeedback = .success("Activated for \(receipt.email ?? receipt.name ?? "this license").")
            pastedPlist = ""
            Task { await model.refresh() }
        } catch {
            inlineFeedback = .error(activationErrorMessage(for: error))
        }
    }

    private func activationErrorMessage(for error: Error) -> String {
        switch error {
        case LicenseStoreError.invalidSignature:
            return "This license didn't pass signature verification. Check the email for a re-send link."
        case LicenseStoreError.malformedReceipt:
            return "That doesn't look like a Gargantua license file. The expected file is a .gargantualicense XML plist."
        case LicenseStoreError.fileIOFailed(let message):
            return "Couldn't write the receipt to disk: \(message)."
        default:
            return error.localizedDescription
        }
    }

    private func openBuyURL() {
        // Placeholder. Phase 5 swaps for the live FastSpring checkout URL.
        guard let url = URL(string: "https://gargantua.dev/buy") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: State helpers

    private var statusIconName: String {
        switch model.state {
        case .licensed: "checkmark.seal.fill"
        case .trial: "hourglass"
        case .expired: "exclamationmark.triangle.fill"
        case .none: "lock.fill"
        }
    }

    private var statusHeadline: String {
        switch model.state {
        case .licensed(let email, _, _): "Licensed to \(email)"
        case .trial(let days) where days == 1: "Trial — 1 day remaining"
        case .trial(let days): "Trial — \(days) days remaining"
        case .expired: "Trial ended"
        case .none: "No license active"
        }
    }

    private var statusDetail: String? {
        switch model.state {
        case .licensed(_, _, let activatedAt):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Activated \(formatter.string(from: activatedAt))."
        case .trial:
            return "Scans and previews stay free forever. Deep Clean, Uninstall, and Quarantine apply require a license after trial."
        case .expired:
            return "Scans still run. Destructive actions are paused until you activate a license."
        case .none:
            return "Activate a license to enable destructive actions."
        }
    }

    private var statusSubtitle: String {
        switch model.state {
        case .licensed: "Thanks for funding development."
        case .trial: "Honesty setting one hundred percent."
        case .expired, .none: "Or build from source — fully unlocked under AGPL-3.0."
        }
    }
}
