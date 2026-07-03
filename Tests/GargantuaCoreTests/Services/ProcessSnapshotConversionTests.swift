import Foundation
import Testing
@testable import GargantuaCore

@Suite("ProcessSnapshot CPU-time conversion")
struct ProcessSnapshotConversionTests {

    @Test("Apple Silicon timebase scales raw ticks by numer/denom")
    func appleSiliconScaling() {
        // Apple Silicon reports timebase 125/3. A process that has burned
        // ~1s of CPU reads 24_060_499 raw ticks; scaled it must land at
        // ~1.0025s in nanoseconds — not the ~24ms the un-converted value
        // would imply.
        let ns = DefaultProcessSnapshotProvider.machTicksToNanoseconds(
            24_060_499, numer: 125, denom: 3
        )
        #expect(ns == 1_002_520_791)
    }

    @Test("Intel timebase of 1/1 is an identity")
    func intelIdentity() {
        let ticks: UInt64 = 987_654_321
        let ns = DefaultProcessSnapshotProvider.machTicksToNanoseconds(
            ticks, numer: 1, denom: 1
        )
        #expect(ns == ticks)
    }

    @Test("Degenerate zero denominator falls back to a no-op")
    func zeroDenomIsSafe() {
        let ns = DefaultProcessSnapshotProvider.machTicksToNanoseconds(
            42, numer: 125, denom: 0
        )
        #expect(ns == 42)
    }

    @Test("Large tick counts scale without overflowing")
    func noOverflowForLongUptime() {
        // ~10 years of a fully-pegged core at the 24MHz Apple Silicon tick
        // rate — well beyond any real process, and still exact.
        let ticks: UInt64 = 24_000_000 * 60 * 60 * 24 * 365 * 10
        let ns = DefaultProcessSnapshotProvider.machTicksToNanoseconds(
            ticks, numer: 125, denom: 3
        )
        // Reference computed the same split way to stay exact.
        let expected = (ticks / 3) &* 125 &+ ((ticks % 3) &* 125) / 3
        #expect(ns == expected)
        #expect(ns > ticks)
    }
}
