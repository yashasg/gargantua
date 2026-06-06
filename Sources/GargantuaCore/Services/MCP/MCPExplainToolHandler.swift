import Foundation

// Handler for the MCP `explain` tool. Shapes an `MCPExplainOutput` value
// produced by an injected `ExplainProvider` into the tool result envelope
// the dispatcher returns to clients.
//
// The handler itself is deliberately thin: input decoding (path-xor-item_id
// mutual exclusion) is enforced by `MCPExplainInput`, and the content of the
// explanation is supplied by the provider. This keeps the handler's test
// surface focused on envelope shaping + error sanitisation, and lets the
// provider swap from today's AI-free shell to an `AIInferenceEngine`-backed
// source without touching the handler.
//
// Scope: the default provider in `Sources/GargantuaMCP/main.swift` returns a
// conservative "review" classification from filesystem metadata for `path`
// inputs, and resolves `item_id` inputs against the scan-session cache to
// return the scan-time classification verbatim.

/// Tool handler for `explain`.
public struct MCPExplainToolHandler: Sendable {

    /// Synchronous explanation provider. Throwing `MCPToolError.invalidParams`
    /// or `.internalError` propagates with the appropriate JSON-RPC code;
    /// any other thrown error is surfaced to the client as a tool-domain
    /// `.failure(...)` result.
    public typealias ExplainProvider = @Sendable (MCPExplainInput) throws -> MCPExplainOutput

    private let explainProvider: ExplainProvider
    private let log: MCPDispatcherLog?

    public init(
        explainProvider: @escaping ExplainProvider,
        log: MCPDispatcherLog? = nil
    ) {
        self.explainProvider = explainProvider
        self.log = log
    }

    /// Bridges this handler to the `MCPToolHandler` shape the dispatcher
    /// expects:
    /// `dispatcher.register(tool: .explain, handler: handler.toolHandler)`.
    public var toolHandler: MCPToolHandler {
        let this = self
        return { arguments in try this.handle(arguments) }
    }

    /// Execute the handler against a decoded arguments payload. Exposed for
    /// unit tests that want to bypass the dispatcher.
    public func handle(_ arguments: MCPToolArguments) throws -> MCPToolCallResult {
        let input = try arguments.decode(MCPExplainInput.self)

        let output: MCPExplainOutput
        do {
            output = try explainProvider(input)
        } catch let error as MCPToolError {
            throw error
        } catch {
            log?("explain handler error: \(error)")
            return .failure("Explain failed: \(MCPEncoding.clientFacingMessage(for: error))")
        }

        let payload = try MCPEncoding.encodeAsJSONAny(output)
        return .structured(payload, summary: Self.summary(for: output))
    }

    // MARK: - Helpers

    private static func summary(for output: MCPExplainOutput) -> String {
        let size = output.size.map { " (\($0))" } ?? ""
        return "\(output.name)\(size): \(output.safety) (\(output.confidence)%). "
            + output.explanation
    }
}

// MARK: - Default filesystem-backed provider

public extension MCPExplainToolHandler {
    /// Lookup function that returns the package receipts claiming a path.
    ///
    /// Production wires this to `PackageReceiptExpander.lookupReceipts(forPath:)`
    /// (see `Sources/GargantuaMCP/main.swift`); tests inject a stub. Returning
    /// an empty array signals "no receipt evidence for this path" — the
    /// provider must not treat the empty-array case as an error.
    typealias ReceiptLookup = @Sendable (String) -> [PackageReceipt]

    /// Resolves an `item_id` from a prior scan to its cached `ScanResult`.
    ///
    /// Production wires this to `MCPScanSessionCache.lookup(id:)` (see
    /// `Sources/GargantuaMCP/main.swift`); tests inject a stub. Returning `nil`
    /// signals "no such id in the current scan session" — the provider turns
    /// that into an `invalidParams` so a stale id is a loud client error, not a
    /// silent fallback to a fabricated path response.
    typealias ItemLookup = @Sendable (String) -> ScanResult?

    /// Classifies an arbitrary absolute path against the rule set, returning the
    /// Trust Layer verdict a scan would assign it, or `nil` when no rule claims
    /// the path.
    ///
    /// Production wires this to `NativeScanAdapter.classify(path:)` (see
    /// `Sources/GargantuaMCP/main.swift`); tests inject a stub. A hit lets the
    /// `path` branch return a real classification instead of the AI-pending
    /// "review" shell.
    typealias PathClassify = @Sendable (String) -> ScanResult?

    /// Default AI-free `ExplainProvider` backed by filesystem metadata.
    ///
    /// Behavior:
    /// - `item_id` inputs resolve against `itemLookup` (the scan-session
    ///   cache). A hit returns the scan-time classification verbatim
    ///   (safety/confidence/explanation), enriched with receipt provenance the
    ///   same way the `path` branch is. A miss throws
    ///   `MCPToolError.invalidParams` — a stale id is a client bug, not a
    ///   silent no-op.
    /// - Missing, empty, or non-absolute `path` inputs throw
    ///   `MCPToolError.invalidParams`. Absolute-only is enforced because
    ///   `MCPPhase2Tools.explain` advertises `path` as an "Absolute filesystem
    ///   path"; accepting relative paths would resolve against the MCP
    ///   process's current working directory and produce surprising results
    ///   depending on launch context.
    /// - An accepted `path` is first run through `pathClassify` (the rule
    ///   engine). When a rule in the active profile claims it, the real
    ///   Trust Layer verdict is returned. Only when no rule matches does the
    ///   provider fall back to the AI-pending shell described below.
    /// - Missing or inaccessible paths (file not found, permission denied)
    ///   return a shell response with no `size`/`lastAccessed` rather than
    ///   erroring. The shell's contract is to always render a conservative
    ///   `"review"` classification for any accepted input; the AI-backed
    ///   provider that replaces this shell will distinguish "unknown
    ///   metadata" from "path not found" explicitly.
    /// - Size is omitted for directories (`.size` returns the inode size, not
    ///   the recursive total) to avoid reporting a misleading small number.
    /// - `lastAccessed` maps to `.modificationDate`: APFS often disables the
    ///   true content-access time, and modification time is the closest
    ///   always-available fallback.
    /// - When `receiptLookup` returns one or more receipts, the provider
    ///   surfaces them under `MCPExplainOutput.receipts` so MCP clients can
    ///   render audit-grade provenance, and prepends a "Owned by package
    ///   <id> (v<version>) installed <date>." sentence to the explanation.
    ///   When the receipt lookup fails or returns empty, the provider falls
    ///   back to the AI-pending shell response unchanged.
    ///
    /// Uses `FileManager.default` directly because `FileManager` is not
    /// `Sendable` and this closure is `@Sendable`. Tests exercise it with
    /// real temporary files.
    static func defaultFilesystemProvider(
        receiptLookup: @escaping ReceiptLookup = { _ in [] },
        itemLookup: @escaping ItemLookup = { _ in nil },
        pathClassify: @escaping PathClassify = { _ in nil }
    ) -> ExplainProvider {
        return { input in
            if let itemId = input.itemId {
                guard let result = itemLookup(itemId) else {
                    throw MCPToolError.invalidParams(
                        "Unknown item_id '\(itemId)'. It may be from an expired or cleared scan session; re-run scan and use a fresh id."
                    )
                }
                return output(from: result, receiptLookup: receiptLookup)
            }
            guard let path = input.path, !path.isEmpty else {
                // `MCPExplainInput` already enforces path-xor-item_id at
                // decode, so this branch is defensive against a future
                // input-shape change that might let both be nil through.
                throw MCPToolError.invalidParams("explain requires a non-empty path.")
            }
            guard path.hasPrefix("/") else {
                throw MCPToolError.invalidParams(
                    "explain requires an absolute filesystem path (starting with '/')."
                )
            }

            // Prefer a real rule-engine verdict: if any rule in the active
            // profile claims this path, return the same classification a scan
            // would. Only when no rule matches do we fall back to the
            // AI-pending "review" shell below.
            if let classified = pathClassify(path) {
                return output(from: classified, receiptLookup: receiptLookup)
            }

            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent

            var size: String?
            var lastAccessed: Date?
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
                if !isDirectory, let bytes = attributes[.size] as? NSNumber {
                    size = AlertItem.formatBytes(Int64(clamping: bytes.int64Value))
                }
                if let modified = attributes[.modificationDate] as? Date {
                    lastAccessed = modified
                }
            }

            let receipts = receiptLookup(path)
            let provenance = receipts.map(MCPReceiptProvenance.init(_:))
            let baseExplanation = "AI-backed analysis is not yet wired; this item is flagged 'review' by default. Inspect before cleanup."
            let explanation: String
            if let leadingProvenance = receiptProvenanceSentence(for: receipts) {
                explanation = "\(leadingProvenance) \(baseExplanation)"
            } else {
                explanation = baseExplanation
            }

            return MCPExplainOutput(
                name: name,
                safety: "review",
                confidence: 50,
                explanation: explanation,
                size: size,
                lastAccessed: lastAccessed,
                receipts: provenance.isEmpty ? nil : provenance
            )
        }
    }

    /// Shape a cached `ScanResult` (resolved from an `item_id`) into the
    /// explain output. Unlike the `path` branch, safety/confidence/explanation
    /// come straight from the scan-time classification rather than the
    /// AI-pending shell, and `size` uses the scan's recursive total (correct
    /// for directories). Receipt provenance is prepended for parity with the
    /// `path` branch.
    private static func output(
        from result: ScanResult,
        receiptLookup: ReceiptLookup
    ) -> MCPExplainOutput {
        let receipts = receiptLookup(result.path)
        let provenance = receipts.map(MCPReceiptProvenance.init(_:))
        let explanation: String
        if let leadingProvenance = receiptProvenanceSentence(for: receipts) {
            explanation = "\(leadingProvenance) \(result.explanation)"
        } else {
            explanation = result.explanation
        }
        return MCPExplainOutput(
            name: result.name,
            safety: result.safety.rawValue,
            confidence: result.confidence,
            explanation: explanation,
            size: AlertItem.formatBytes(result.size),
            lastAccessed: result.lastAccessed,
            receipts: provenance.isEmpty ? nil : provenance
        )
    }

    /// Build a one-line "Owned by package <id> (v<version>) installed <date>."
    /// sentence from receipt evidence, or `nil` when the array is empty.
    /// Multiple receipts join with "; " so a path claimed by several
    /// packages still produces a single readable sentence.
    private static func receiptProvenanceSentence(
        for receipts: [PackageReceipt]
    ) -> String? {
        guard !receipts.isEmpty else { return nil }
        let parts = receipts.map { receipt -> String in
            let version = receipt.version.map { " (v\($0))" } ?? ""
            let installed = receipt.installDate.map { " installed \(Self.dateFormatter.string(from: $0))" } ?? ""
            return "\(receipt.pkgID)\(version)\(installed)"
        }
        return "Owned by package \(parts.joined(separator: "; "))."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        // Pin POSIX so non-Gregorian system locales (Buddhist, Japanese era,
        // Hebrew, Persian) do not render `yyyy` in their own calendar — TN1480.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private extension MCPReceiptProvenance {
    init(_ receipt: PackageReceipt) {
        self.init(
            pkgID: receipt.pkgID,
            pkgVersion: receipt.version,
            installDate: receipt.installDate
        )
    }
}
