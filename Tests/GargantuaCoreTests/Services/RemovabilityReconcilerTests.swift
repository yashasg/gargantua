import Foundation
import Testing
@testable import GargantuaCore

@Suite("RemovabilityReconciler")
struct RemovabilityReconcilerTests {
    private func result(
        id: String = "r1",
        path: String,
        safety: SafetyLevel = .review,
        tags: [String] = [],
        category: String = "system_logs"
    ) -> ScanResult {
        ScanResult(
            id: id,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            size: 1024,
            safety: safety,
            confidence: 80,
            explanation: "test",
            source: SourceAttribution(name: "Test"),
            category: category,
            tags: tags
        )
    }

    private let noProtectedRoots = ProtectedRootPolicy(entries: [])

    @Test("Plain user-owned items are removable")
    func userOwnedRemovable() {
        let recon = RemovabilityReconciler(protectedRoots: noProtectedRoots)
        let r = result(path: "/Users/x/Library/Caches/app/blob", safety: .safe, tags: ["cache"])
        #expect(recon.removability(for: r) == .removable)
    }

    @Test("Protected-root match is view-only with the policy's reason")
    func protectedRootViewOnly() {
        let policy = ProtectedRootPolicy(entries: [
            ProtectedRootEntry(path: "/Users/x/Projects", reason: "User project root", source: .user),
        ])
        let recon = RemovabilityReconciler(protectedRoots: policy)
        let r = result(path: "/Users/x/Projects", safety: .review)
        #expect(recon.removability(for: r).viewOnlyReason == "User project root")
    }

    @Test("Protected safety level is view-only")
    func protectedSafetyViewOnly() {
        let recon = RemovabilityReconciler(protectedRoots: noProtectedRoots)
        let r = result(path: "/Library/Foo", safety: .protected_)
        #expect(recon.removability(for: r).viewOnlyReason != nil)
    }

    @Test("Privileged path in the allowlist is removable")
    func privilegedAllowlistedRemovable() {
        let recon = RemovabilityReconciler(protectedRoots: noProtectedRoots)
        let r = result(
            path: "/private/var/db/powerlog/Library/x",
            safety: .review,
            tags: ["privileged"]
        )
        #expect(recon.removability(for: r) == .removable)
    }

    @Test("Privileged path NOT in the allowlist is view-only (live diagnostics store)")
    func privilegedNotAllowlistedViewOnly() {
        let recon = RemovabilityReconciler(protectedRoots: noProtectedRoots)
        let r = result(
            path: "/private/var/db/diagnostics/logd.1.log",
            safety: .review,
            tags: ["privileged"]
        )
        #expect(recon.removability(for: r).viewOnlyReason != nil)
    }

    @Test("map covers every result")
    func mapCoversAll() {
        let recon = RemovabilityReconciler(protectedRoots: noProtectedRoots)
        let results = [
            result(id: "a", path: "/Users/x/Library/Caches/a", safety: .safe),
            result(id: "b", path: "/private/var/db/diagnostics/b", safety: .review, tags: ["privileged"]),
        ]
        let map = recon.map(for: results)
        #expect(map["a"] == .removable)
        #expect(map["b"]?.isRemovable == false)
    }
}
