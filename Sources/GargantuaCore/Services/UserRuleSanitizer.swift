import Foundation

/// Clamps the authority of user-authored rules before they enter the scan
/// pipeline.
///
/// Bundled rules ship in a signed snapshot reviewed via public PRs, so they are
/// trusted to declare `safe` classifications and profile-scoped overrides. User
/// rules carry no such review, so they are loaded with reduced privilege:
///
///   * Safety is floored to `review` — a user rule may surface a candidate but
///     can never mark it one-click `safe`. (`protected` is left intact; it only
///     makes a rule *more* conservative.)
///   * Profile-scoped `safetyOverrides` are dropped — they are the exact escape
///     hatch the clamp exists to close.
///   * On id collision with a bundled rule, the user rule is dropped so it can
///     never shadow or weaken a bundled classification.
///
/// Command rules additionally go through `CommandActionRuleLoader`'s existing
/// validation (protected-root rejection, advanced-category review requirement)
/// at load time; this sanitizer floors their declared safety on top of that.
public enum UserRuleSanitizer {
    /// Reserved tag stamped onto every user-authored rule. It lets the Trust
    /// Layer recognize user provenance after the rule leaves the loader —
    /// `SafetyClassifier` uses it to re-cap any classification (including one
    /// reached via a profile-scoped override) so a user rule can never end up
    /// `safe`. This is defense-in-depth behind the load-time `floor`.
    public static let originTag = "user-authored"

    /// Floor a classification so user rules can never assert `safe`.
    static func floor(_ level: SafetyLevel) -> SafetyLevel {
        level == .safe ? .review : level
    }

    private static func tagged(_ tags: [String]) -> [String] {
        tags.contains(originTag) ? tags : tags + [originTag]
    }

    public static func sanitize(_ rule: ScanRule) -> ScanRule {
        ScanRule(
            id: rule.id,
            name: rule.name,
            paths: rule.paths,
            pattern: rule.pattern,
            exclude: rule.exclude,
            skipIfProcessRunning: rule.skipIfProcessRunning,
            presenceGuards: rule.presenceGuards,
            contentGuards: rule.contentGuards,
            matchFilters: rule.matchFilters,
            minSize: rule.minSize,
            safety: floor(rule.safety),
            confidence: rule.confidence,
            explanation: rule.explanation,
            source: rule.source,
            regenerates: rule.regenerates,
            regenerateCommand: rule.regenerateCommand,
            category: rule.category,
            tags: tagged(rule.tags),
            safetyOverrides: [],
            provenance: rule.provenance
        )
    }

    public static func sanitize(_ rule: RemnantRule) -> RemnantRule {
        RemnantRule(
            id: rule.id,
            name: rule.name,
            category: rule.category,
            pathTemplates: rule.pathTemplates,
            pattern: rule.pattern,
            exclude: rule.exclude,
            safety: floor(rule.safety),
            confidence: rule.confidence,
            explanation: rule.explanation,
            source: rule.source,
            appliesTo: rule.appliesTo,
            regenerates: rule.regenerates,
            tags: tagged(rule.tags)
        )
    }

    public static func sanitize(_ rule: CommandActionRule) -> CommandActionRule {
        CommandActionRule(
            id: rule.id,
            name: rule.name,
            tool: rule.tool,
            arguments: rule.arguments,
            dryRunArguments: rule.dryRunArguments,
            safety: floor(rule.safety),
            confidence: rule.confidence,
            explanation: rule.explanation,
            consequence: rule.consequence,
            category: rule.category,
            regenerates: rule.regenerates,
            regenerateCommand: rule.regenerateCommand,
            affectedRoots: rule.affectedRoots,
            preconditions: rule.preconditions,
            source: rule.source,
            tags: tagged(rule.tags)
        )
    }

    /// Merge bundled and user rules, sanitizing the user rules and dropping any
    /// whose `id` already exists in the bundled set (bundled wins) or that
    /// collide with an already-accepted user rule.
    ///
    /// Returns the merged list plus the ids that were dropped, so callers can
    /// surface the collisions as warnings.
    public static func merge<T: Identifiable>(
        bundled: [T],
        user: [T],
        sanitizing: (T) -> T
    ) -> (rules: [T], droppedIDs: [String]) where T.ID == String {
        var seen = Set(bundled.map(\.id))
        var merged = bundled
        var dropped: [String] = []

        for rule in user {
            guard seen.insert(rule.id).inserted else {
                dropped.append(rule.id)
                continue
            }
            merged.append(sanitizing(rule))
        }

        return (merged, dropped)
    }
}
