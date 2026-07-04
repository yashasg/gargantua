import Foundation
import Testing
@testable import GargantuaCore

@Suite("ClaudeCodeAgentSessionController scan cache fallback — wire round-trip")
@MainActor
struct ClaudeCodeAgentScanCacheFallbackTests {
    @Test("scanResult(from:) carries a recorded scan_time_resolved_parent through to ScanResult")
    func recordedParentRoundTrips() {
        let item = MCPScanItem(
            id: "chrome_cache_001",
            name: "Chrome Browser Cache",
            path: "/Volumes/Ext/dev/node_modules",
            size: "10.5 GB",
            safety: "safe",
            confidence: 99,
            explanation: "Browser cache files. Regenerated automatically.",
            source: "Google Chrome",
            category: "dev_artifacts",
            scanTimeResolvedParent: "/Volumes/Ext/dev"
        )
        let result = ClaudeCodeAgentSessionController.scanResult(from: item)
        #expect(result?.scanTimeResolvedParent == "/Volumes/Ext/dev")
    }

    @Test("scanResult(from:) leaves scan_time_resolved_parent nil when the wire item didn't carry one")
    func nilParentStaysNil() {
        let item = MCPScanItem(
            id: "chrome_cache_001",
            name: "Chrome Browser Cache",
            path: "/Volumes/Ext/dev/node_modules",
            size: "10.5 GB",
            safety: "safe",
            confidence: 99,
            explanation: "Browser cache files. Regenerated automatically.",
            source: "Google Chrome",
            category: "dev_artifacts",
            scanTimeResolvedParent: nil
        )
        let result = ClaudeCodeAgentSessionController.scanResult(from: item)
        #expect(result?.scanTimeResolvedParent == nil)
    }
}
