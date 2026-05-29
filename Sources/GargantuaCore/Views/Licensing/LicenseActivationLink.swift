import Foundation
import GargantuaLicensing
import OSLog

private let logger = Logger(subsystem: "com.gargantua.licensing", category: "ActivationLink")

/// Handles the `gargantua://activate?key=GARG-…` deep link. Polar's
/// post-checkout redirect (or the license email's auto-activate link) opens
/// this; we parse the key and run it through the same activation path as the
/// Settings pane. No-ops in source builds (the gate is always licensed there).
public enum LicenseActivationLink {
    public static func handle(_ url: URL) {
        guard url.scheme == "gargantua", url.host == "activate" else { return }
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let key = components.queryItems?.first(where: { $0.name == "key" })?.value,
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger.info("Activation link had no key; ignoring")
            return
        }

        Task { @MainActor in
            let result = await LicenseStateModel.shared.activate(key: key)
            switch result {
            case .success:
                logger.info("Activated via deep link")
            case .failure(let error):
                logger.warning("Deep-link activation failed: \(String(describing: error))")
            }
        }
    }
}
