import GargantuaLicensing
import SwiftUI

/// Presented when a destructive action is intercepted by `LicenseGate`. Mirrors
/// the `DestructiveConfirmSheet` chrome so the visual language stays consistent
/// across confirmation modals. Phase 4 wires the Buy button to FastSpring's
/// checkout URL — for now it opens a placeholder.
public struct UnlockGargantuaSheet: View {
    public let reason: BlockReason
    public let onDismiss: () -> Void
    public let onBuy: () -> Void
    public let onActivate: (String) -> ActivationOutcome

    public enum ActivationOutcome: Equatable {
        case ok
        case error(String)
    }

    @State private var keyDraft: String = ""
    @State private var feedback: String?
    @State private var showsKeyField = false

    public init(
        reason: BlockReason,
        onDismiss: @escaping () -> Void,
        onBuy: @escaping () -> Void,
        onActivate: @escaping (String) -> ActivationOutcome
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

            if showsKeyField {
                VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
                    Text("License key")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)

                    TextField("Paste the key from your purchase email", text: $keyDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(GargantuaFonts.monoData)
                        .lineLimit(3 ... 6)

                    if let feedback {
                        Text(feedback)
                            .font(GargantuaFonts.caption)
                            .foregroundStyle(GargantuaColors.protected_)
                    }
                }
            }

            HStack(spacing: GargantuaSpacing.space3) {
                if !showsKeyField {
                    Button(action: { showsKeyField = true }, label: {
                        Text("Already bought? Enter key")
                            .font(GargantuaFonts.body)
                            .foregroundStyle(GargantuaColors.ink2)
                    })
                    .buttonStyle(.plain)
                }

                Spacer()

                GargantuaButton("Dismiss", tone: .neutral) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                if showsKeyField {
                    GargantuaButton("Activate", icon: "key.fill", tone: .primary) {
                        let outcome = onActivate(keyDraft)
                        switch outcome {
                        case .ok:
                            onDismiss()
                        case .error(let message):
                            feedback = message
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    GargantuaButton("Buy Gargantua · $29", icon: "arrow.up.right.square", tone: .primary) {
                        onBuy()
                    }
                    .keyboardShortcut(.defaultAction)
                }
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

    private var title: String {
        switch reason {
        case .trialExpired: "Tether severed"
        case .noLicense: "Activation required"
        }
    }

    private var subtitle: String {
        switch reason {
        case .trialExpired:
            "Your 14-day window has closed. Activate Gargantua to keep applying destructive operations. Scans and previews stay open."
        case .noLicense:
            "Sign the manifest to continue. Activate a license — or finish the trial first."
        }
    }
}
