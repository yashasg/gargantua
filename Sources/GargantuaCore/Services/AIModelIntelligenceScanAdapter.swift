import Foundation

/// Finds high-signal local AI model cleanup candidates that static path rules
/// cannot express: same-name/same-size duplicates and orphan model weights.
public struct AIModelIntelligenceScanAdapter: ScanAdapter {
    public static let category = "ai_models"
    public static let resultIDPrefix = "ai-model-intelligence:"
    public static let tag = "ai-model-intelligence"
    public static let duplicateTag = "ai-model-duplicate"
    public static let orphanTag = "ai-model-orphan"
    public static let modelTag = "ai-model-known-store"

    private static let modelExtensions: Set<String> = [
        "bin", "ckpt", "gguf", "onnx", "pt", "pth", "safetensors",
    ]

    private let policy: AIModelScanPolicy
    private let categories: Set<String>?

    public init(policy: AIModelScanPolicy, categories: Set<String>? = nil) {
        self.policy = policy
        self.categories = categories
    }

    public static func loadDefaults(
        categories: Set<String>? = nil,
        scanRoots: [URL]? = nil,
        excludedPaths: Set<String> = [],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AIModelIntelligenceScanAdapter {
        AIModelIntelligenceScanAdapter(
            policy: AIModelScanPolicy(
                knownStores: defaultKnownStores(homeDirectory: homeDirectory),
                orphanRoots: defaultOrphanRoots(
                    homeDirectory: homeDirectory,
                    scanRoots: scanRoots
                ),
                excludedPaths: excludedPaths
            ),
            categories: categories
        )
    }

    public func scan(progress: ScanProgress?) async throws -> [ScanResult] {
        try await scan(progress: progress, observer: nil)
    }

    public func scan(
        progress: ScanProgress?,
        observer: (any ScanProgressObserving)?
    ) async throws -> [ScanResult] {
        guard categories == nil || categories?.contains(Self.category) == true else { return [] }

        let findings = discoverFindings()
        let results = makeScanResults(from: findings)
        for result in results {
            observer?.didEmit(ScanProgressEvent(
                path: result.path,
                outcome: .match,
                bytes: result.size
            ))
        }
        return results
    }

    public func discoverFindings() -> AIModelScanFindings {
        let candidates = uniqueCandidates()
        let grouped = Dictionary(grouping: candidates, by: \.duplicateKey)
        let duplicateGroups = grouped.values
            .filter { $0.count > 1 }
            .map { group -> AIModelDuplicateGroup in
                let candidates = group.sorted { lhs, rhs in
                    lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return AIModelDuplicateGroup(
                    id: Self.sanitizedID(candidates.first?.duplicateKey ?? UUID().uuidString),
                    candidates: candidates
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
                return lhs.id < rhs.id
            }

        let duplicatePaths = Set(duplicateGroups.flatMap { $0.candidates.map(\.path) })
        let bySize: (AIModelFileCandidate, AIModelFileCandidate) -> Bool = { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        let orphans = candidates
            .filter { !$0.isKnownStore && !duplicatePaths.contains($0.path) }
            .sorted(by: bySize)
        let knownStore = candidates
            .filter { $0.isKnownStore && !duplicatePaths.contains($0.path) }
            .sorted(by: bySize)

        return AIModelScanFindings(
            duplicateGroups: duplicateGroups,
            orphanCandidates: orphans,
            knownStoreCandidates: knownStore
        )
    }
}

private extension AIModelIntelligenceScanAdapter {
    private func uniqueCandidates() -> [AIModelFileCandidate] {
        var byPath: [String: AIModelFileCandidate] = [:]

        // Managed-manifest stores (Ollama, Hugging Face) map files to models via
        // a manifest over shared content-addressed blobs. Deleting a blob by path
        // dangles other manifests, so they are never surfaced as path-delete
        // duplicate/orphan candidates here — a manifest-aware pass owns them.
        for store in policy.knownStores where store.kind == .flatFile {
            for root in store.roots {
                for candidate in scan(root: root, store: store) {
                    byPath[AIModelScanPolicy.normalizedPath(candidate.path)] = candidate
                }
            }
        }

        for root in policy.orphanRoots {
            for candidate in scan(root: root, store: nil) {
                let key = AIModelScanPolicy.normalizedPath(candidate.path)
                if byPath[key] == nil {
                    byPath[key] = candidate
                }
            }
        }

        return Array(byPath.values)
    }

    private func scan(root: URL, store: AIModelStoreDefinition?) -> [AIModelFileCandidate] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        let state = WalkState(
            maxEntries: policy.maxEntriesPerRoot,
            timeBudget: policy.timeBudgetPerRoot
        )
        let context = WalkContext(
            includeHidden: store != nil,
            store: store,
            state: state
        )
        var out: [AIModelFileCandidate] = []
        walk(
            at: root,
            depth: 0,
            context: context,
            into: &out
        )
        return out
    }

    private func walk(
        at url: URL,
        depth: Int,
        context: WalkContext,
        into out: inout [AIModelFileCandidate]
    ) {
        guard !context.state.shouldStop, depth <= policy.maxDepth else { return }
        guard policy.protectionReason(for: url.path) == nil,
              !policy.isExcluded(path: url.path) else {
            return
        }

        let options: FileManager.DirectoryEnumerationOptions = context.includeHidden ? [] : [.skipsHiddenFiles]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .contentAccessDateKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: options
        )) ?? []

        for child in children {
            context.state.incrementEntries()
            if context.state.shouldStop { return }
            if policy.protectionReason(for: child.path) != nil || policy.isExcluded(path: child.path) {
                continue
            }

            let values = try? child.resourceValues(forKeys: [
                .contentAccessDateKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values?.isSymbolicLink == true { continue }

            if values?.isDirectory == true {
                walk(
                    at: child,
                    depth: depth + 1,
                    context: context,
                    into: &out
                )
            } else if let candidate = makeCandidate(url: child, values: values, store: context.store) {
                out.append(candidate)
            }
        }
    }

    private func makeCandidate(
        url: URL,
        values: URLResourceValues?,
        store: AIModelStoreDefinition?
    ) -> AIModelFileCandidate? {
        let ext = url.pathExtension.lowercased()
        let extensionMatches = Self.modelExtensions.contains(ext)
        let extensionlessStoreBlob = ext.isEmpty && store?.includeExtensionlessLargeFiles == true
        guard extensionMatches || extensionlessStoreBlob else { return nil }

        let size = Int64(values?.fileSize ?? 0)
        guard size >= policy.minimumModelFileSize else { return nil }

        let source = store?.displayName ?? "Orphan model file"
        return AIModelFileCandidate(
            path: url.path,
            fileName: url.lastPathComponent,
            fileExtension: ext.isEmpty ? nil : ext,
            size: size,
            sourceName: source,
            isKnownStore: store != nil || policy.knownStore(for: url.path) != nil,
            modelFamily: Self.inferModelFamily(from: url.lastPathComponent),
            lastAccessed: values?.contentAccessDate ?? values?.contentModificationDate
        )
    }

    private func makeScanResults(from findings: AIModelScanFindings) -> [ScanResult] {
        let duplicateResults = findings.duplicateGroups.flatMap(makeDuplicateResults)
        let orphanResults = findings.orphanCandidates.enumerated().map { index, candidate in
            makeOrphanResult(candidate: candidate, index: index)
        }
        let knownStoreResults = findings.knownStoreCandidates.enumerated().map { index, candidate in
            makeKnownStoreResult(candidate: candidate, index: index)
        }
        return duplicateResults + orphanResults + knownStoreResults
    }

    private func makeDuplicateResults(group: AIModelDuplicateGroup) -> [ScanResult] {
        group.candidates.enumerated().map { index, candidate in
            ScanResult(
                id: "\(Self.resultIDPrefix)duplicate-\(group.id)-\(index)",
                name: "Duplicate model candidate — \(candidate.fileName)",
                path: candidate.path,
                size: candidate.size,
                safety: .review,
                confidence: 68,
                explanation: duplicateExplanation(group: group, candidate: candidate),
                source: SourceAttribution(name: candidate.sourceName),
                lastAccessed: candidate.lastAccessed,
                category: Self.category,
                tags: tags(
                    candidate: candidate,
                    extra: [Self.duplicateTag, "ai-model-duplicate-group-\(group.id)"]
                ),
                regenerates: false
            )
        }
    }

    private func makeOrphanResult(candidate: AIModelFileCandidate, index: Int) -> ScanResult {
        ScanResult(
            id: "\(Self.resultIDPrefix)orphan-\(Self.sanitizedID(candidate.path))-\(index)",
            name: "Orphan model weight — \(candidate.fileName)",
            path: candidate.path,
            size: candidate.size,
            safety: .review,
            confidence: 64,
            explanation: orphanExplanation(candidate: candidate),
            source: SourceAttribution(name: candidate.sourceName),
            lastAccessed: candidate.lastAccessed,
            category: Self.category,
            tags: tags(candidate: candidate, extra: [Self.orphanTag, "orphan"]),
            regenerates: false
        )
    }

    private func makeKnownStoreResult(candidate: AIModelFileCandidate, index: Int) -> ScanResult {
        ScanResult(
            id: "\(Self.resultIDPrefix)model-\(Self.sanitizedID(candidate.path))-\(index)",
            name: "\(candidate.sourceName) model — \(candidate.fileName)",
            path: candidate.path,
            size: candidate.size,
            safety: .review,
            confidence: 72,
            explanation: knownStoreExplanation(candidate: candidate),
            source: SourceAttribution(name: candidate.sourceName),
            lastAccessed: candidate.lastAccessed,
            category: Self.category,
            tags: tags(
                candidate: candidate,
                extra: [Self.modelTag] + modelKindTags(for: candidate)
            ),
            regenerates: false
        )
    }

    private func knownStoreExplanation(candidate: AIModelFileCandidate) -> String {
        let family = candidate.modelFamily.map { " Inferred family: \($0)." } ?? ""
        let kind = Self.inferModelKind(from: candidate.path).map { " (\($0.label))" } ?? ""
        return "Individual \(candidate.sourceName) model file\(kind)." +
            "\(family) Remove just this model — re-download cost is user-specific, so this stays review-only."
    }

    private func modelKindTags(for candidate: AIModelFileCandidate) -> [String] {
        guard let kind = Self.inferModelKind(from: candidate.path) else { return [] }
        return ["model-kind-\(kind.rawValue)"]
    }

    private func duplicateExplanation(
        group: AIModelDuplicateGroup,
        candidate: AIModelFileCandidate
    ) -> String {
        let family = candidate.modelFamily.map { " Inferred family: \($0)." } ?? ""
        return "\(group.candidates.count) model-looking files share this filename and byte size." +
            "\(family) Gargantua does not inspect model contents, so this stays review-only."
    }

    private func orphanExplanation(candidate: AIModelFileCandidate) -> String {
        let family = candidate.modelFamily.map { " Inferred family: \($0)." } ?? ""
        return "Large \(candidate.fileExtension.map { ".\($0)" } ?? "model") file outside known active model stores." +
            "\(family) Re-download cost and provenance are user-specific, so this stays review-only."
    }

    private func tags(candidate: AIModelFileCandidate, extra: [String]) -> [String] {
        var tags = ["ai", "models", Self.tag] + extra
        if let family = candidate.modelFamily {
            tags.append("model-family-\(Self.sanitizedID(family))")
        }
        return Array(Set(tags)).sorted()
    }

    /// The role a model file plays, inferred from the conventional store
    /// subdirectory layout (ComfyUI / SD-WebUI organize weights by kind).
    enum ModelKind: String {
        case checkpoint
        case lora
        case vae
        case controlnet
        case embedding

        var label: String {
            switch self {
            case .checkpoint: return "checkpoint"
            case .lora: return "LoRA"
            case .vae: return "VAE"
            case .controlnet: return "ControlNet"
            case .embedding: return "embedding"
            }
        }
    }

    /// Match the model kind from a path component (e.g. `.../models/loras/foo`).
    /// Directory names are the reliable signal; filenames vary too much.
    static func inferModelKind(from path: String) -> ModelKind? {
        let components = Set(path.lowercased().split(separator: "/").map(String.init))
        let mapping: [(String, ModelKind)] = [
            ("checkpoints", .checkpoint),
            ("checkpoint", .checkpoint),
            ("loras", .lora),
            ("lora", .lora),
            ("vae", .vae),
            ("controlnet", .controlnet),
            ("controlnets", .controlnet),
            ("embeddings", .embedding),
            ("embedding", .embedding),
        ]
        return mapping.first { components.contains($0.0) }?.1
    }

    private static func inferModelFamily(from fileName: String) -> String? {
        let lower = fileName.lowercased()
        let families: [(String, String)] = [
            ("stable-diffusion", "Stable Diffusion"),
            ("sdxl", "Stable Diffusion XL"),
            ("deepseek", "DeepSeek"),
            ("mistral", "Mistral"),
            ("mixtral", "Mixtral"),
            ("llama", "Llama"),
            ("gemma", "Gemma"),
            ("qwen", "Qwen"),
            ("whisper", "Whisper"),
            ("clip", "CLIP"),
            ("bert", "BERT"),
            ("flux", "FLUX"),
            ("phi", "Phi"),
        ]
        return families.first { lower.contains($0.0) }?.1
    }

    private static func sanitizedID(_ raw: String) -> String {
        let mapped = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        return String(mapped)
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
    }
}

private extension AIModelIntelligenceScanAdapter {
    struct WalkContext {
        let includeHidden: Bool
        let store: AIModelStoreDefinition?
        let state: WalkState
    }

    final class WalkState {
        let maxEntries: Int
        let timeBudget: TimeInterval
        let start = Date()
        var entries = 0

        init(maxEntries: Int, timeBudget: TimeInterval) {
            self.maxEntries = maxEntries
            self.timeBudget = timeBudget
        }

        var shouldStop: Bool {
            entries >= maxEntries || Date().timeIntervalSince(start) > timeBudget
        }

        func incrementEntries() {
            entries += 1
        }
    }
}
