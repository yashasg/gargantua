import SwiftUI

/// The dominant cause behind a batch of cleanup failures, with the matching
/// title, remediation copy, and a deep-link to the exact System Settings pane.
/// Surfaced once above the failed-item list in the cleanup summary.
enum PermissionFailureGuidance {
    /// Full Disk Access is genuinely missing.
    case fullDiskAccess
    /// Finder Automation (Apple Events) was denied.
    case automation
    /// Items are owned by macOS or another user; the privileged helper is
    /// present but needs approval.
    case ownership
    /// Items are owned by the system but this build ships no privileged helper
    /// (an AGPL source build, or a fork signed by another team), so elevated
    /// removal can never work here.
    case systemUnavailable
    /// The privileged helper is active, but these items still couldn't be
    /// removed — owned by root / another user, or in use. No approval helps.
    case systemResidual

    var title: String {
        switch self {
        case .fullDiskAccess: "These items require Full Disk Access"
        case .automation: "These items need Automation permission"
        case .ownership: "These items are owned by the system"
        case .systemUnavailable: "This build can't remove system-owned items"
        case .systemResidual: "Some items couldn't be removed"
        }
    }

    var detail: String {
        switch self {
        case .fullDiskAccess:
            "Open System Settings, click the \"+\" button, then add Gargantua from your Applications folder."
        case .automation:
            "Gargantua moves items to the Trash through Finder. Allow it to control Finder under Automation, "
                + "or it will fall back to the direct Trash API."
        case .ownership:
            "Full Disk Access can't delete files owned by macOS or another user. Approve Gargantua's privileged "
                + "helper under Login Items & Extensions so it can remove them, then run the clean again."
        case .systemUnavailable:
            "Files owned by macOS or another user need Gargantua's privileged helper, which only the signed "
                + "release ships. Install it with Homebrew (brew install --cask gargantua), or build from source "
                + "with your own Developer ID. Files you own were still cleaned."
        case .systemResidual:
            "These are owned by macOS or another user, or are in use by a running app (for example a root-owned "
                + "app already in the Trash), so they couldn't be removed even with Gargantua's privileged helper. "
                + "Each item's reason is shown below; the rest were cleaned."
        }
    }

    /// Some states have no actionable button — the situation is informational.
    var buttonLabel: String? {
        switch self {
        case .fullDiskAccess: "Open Full Disk Access Settings"
        case .automation: "Open Automation Settings"
        case .ownership: "Open Login Items & Extensions"
        case .systemUnavailable: "Get the Signed Release"
        case .systemResidual: nil
        }
    }

    var buttonIcon: String {
        switch self {
        case .fullDiskAccess, .automation, .ownership: "gear"
        case .systemUnavailable: "arrow.down.circle"
        case .systemResidual: "info.circle"
        }
    }

    var actionURL: URL? {
        switch self {
        case .fullDiskAccess:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .ownership:
            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        case .systemUnavailable:
            URL(string: "https://github.com/inceptyon-labs/gargantua/releases/latest")
        case .systemResidual:
            nil
        }
    }
}

struct PermissionFailurePrompt: View {
    let guidance: PermissionFailureGuidance

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            HStack(spacing: GargantuaSpacing.space2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(GargantuaColors.review)

                Text(guidance.title)
                    .font(GargantuaFonts.label)
                    .foregroundStyle(GargantuaColors.ink)
            }

            Text(guidance.detail)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let actionURL = guidance.actionURL, let buttonLabel = guidance.buttonLabel {
                Button {
                    openURL(actionURL)
                } label: {
                    HStack(spacing: GargantuaSpacing.space1) {
                        Image(systemName: guidance.buttonIcon)
                            .font(.system(size: 11))
                        Text(buttonLabel)
                            .font(GargantuaFonts.caption)
                    }
                    .foregroundStyle(GargantuaColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(GargantuaSpacing.space3)
        .background(GargantuaColors.review.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                .stroke(GargantuaColors.review.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
    }
}
