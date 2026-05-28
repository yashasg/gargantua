import AppKit
import GargantuaLicensing
import SwiftUI

/// Presented when a destructive action is intercepted by `LicenseGate`. Mirrors
/// the `DestructiveConfirmSheet` chrome so the visual language stays consistent
/// across confirmation modals. Phase 5 wires the Buy button to FastSpring's
/// checkout URL — for now it opens a placeholder.
public struct UnlockGargantuaSheet: View {
    public let reason: BlockReason
    public let onDismiss: () -> Void
    public let onBuy: () -> Void
    public let onActivate: (URL) -> ActivationOutcome

    public enum ActivationOutcome: Equatable {
        case ok
        case error(String)
    }

    @State private var feedback: String?

    public init(
        reason: BlockReason,
        onDismiss: @escaping () -> Void,
        onBuy: @escaping () -> Void,
        onActivate: @escaping (URL) -> ActivationOutcome
    ) {
        self.reason = reason
        self.onDismiss = onDismiss
        self.onBuy = onBuy
        self.onActivate = onActivate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space4) {
            HStack(alignment: .top, spacing: GargantuaSpacing.space3) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(GargantuaColors.review)

                VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
                    Text(title)
                        .font(GargantuaFonts.title)
                        .foregroundStyle(GargantuaColors.ink)

                    Text(subtitle)
                        .font(GargantuaFonts.body)
                        .foregroundStyle(GargantuaColors.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let feedback {
                Text(feedback)
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.protected_)
            }

            HStack(spacing: GargantuaSpacing.space3) {
                Button(action: pickLicenseFile, label: {
                    Text("Open license file…")
                        .font(GargantuaFonts.body)
                        .foregroundStyle(GargantuaColors.ink2)
                })
                .buttonStyle(.plain)

                Spacer()

                GargantuaButton("Dismiss", tone: .neutral) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                GargantuaButton("Buy Gargantua · $29", icon: "arrow.up.right.square", tone: .primary) {
                    onBuy()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(GargantuaSpacing.space5)
        .frame(width: 460)
        .background(GargantuaColors.surface3)
        .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: GargantuaRadius.large)
                .stroke(GargantuaColors.borderEm, lineWidth: 1)
        )
    }

    private func pickLicenseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["gargantualicense", "plist", "xml"]
        panel.prompt = "Activate"
        panel.title = "Open Gargantua license file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let outcome = onActivate(url)
        switch outcome {
        case .ok:
            onDismiss()
        case .error(let message):
            feedback = message
        }
    }

    private var title: String {
        switch reason {
        case .trialExpired: "Tether severed"
        case .noLicense: "Activation required"
        }
    }

    private var subtitle: String {
        switch reason {
        case .trialExpired:
            "Your 14-day window has closed. Open your .gargantualicense file to keep applying destructive operations. Scans and previews stay open."
        case .noLicense:
            "Sign the manifest to continue. Open the license file from your purchase email — or finish the trial first."
        }
    }
}
