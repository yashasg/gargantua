import Foundation

/// Which provider powers an on-demand "Explain deeper" request from the
/// explanation sheet. Inline explanations always run locally (Template/MLX);
/// this only selects the escalation target when the user asks for more.
public enum DeeperExplainProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Hosted Claude over the public Anthropic API, billed to a user-supplied
    /// API key (the existing Cloud AI path).
    case cloud
    /// The user's local `claude` CLI, billed to their Claude subscription —
    /// no API key required. Reuses the Claude Code agent's configured CLI.
    case claudeCode

    public static let userDefaultsKey = "deeperExplainProvider"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cloud: "Cloud (Anthropic)"
        case .claudeCode: "Claude Code"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .cloud: "Hosted Claude over the Anthropic API. Needs an API key and is metered against your monthly cap."
        case .claudeCode: "Your local Claude Code CLI, billed to your Claude subscription. No API key — needs the agent enabled below."
        }
    }

    public static func stored(in defaults: UserDefaults = .standard) -> DeeperExplainProvider {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let provider = DeeperExplainProvider(rawValue: rawValue)
        else {
            return .cloud
        }
        return provider
    }

    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}
