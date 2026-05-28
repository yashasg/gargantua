import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseStore")
struct LicenseStoreTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-licensing-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).gargantualicense", isDirectory: false)
    }

    private func makeStore(at url: URL) -> LicenseStore {
        LicenseStore(fileURL: url, publicKey: TestKeys.developmentPublicKey)
    }

    @Test("Signed AquaticPrime plist round-trips through save → load")
    func roundTripsValidPlist() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let plistData = try TestKeys.signedLicensePlist()

        let saved = try store.save(plistData: plistData)
        #expect(saved.email == "test@example.com")
        #expect(saved.name == "Test User")
        #expect(saved.product == "Gargantua")

        let loaded = store.loadValidReceipt()
        #expect(loaded?.email == "test@example.com")
        #expect(loaded?.fields == saved.fields)
    }

    @Test("Loading from a non-existent file returns nil")
    func missingFileReturnsNil() {
        let store = makeStore(at: tempFileURL())
        #expect(store.loadValidReceipt() == nil)
    }

    @Test("Plist with tampered customer field fails signature verification")
    func tamperedFieldRejected() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let plistData = try TestKeys.signedLicensePlist(fields: [
            "Product": "Gargantua",
            "Name": "Real User",
            "Email": "real@example.com",
            "Order": "ORDER-1",
            "Timestamp": "Thu, 28 May 2026 12:00:00 +0000",
        ])

        // Tamper: swap the email to a different value, keep the original signature.
        guard let dict = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any] else {
            Issue.record("Couldn't decode test plist")
            return
        }
        var tampered = dict
        tampered["Email"] = "attacker@example.com"
        let tamperedData = try PropertyListSerialization.data(
            fromPropertyList: tampered, format: .xml, options: 0
        )

        #expect(throws: LicenseStoreError.invalidSignature) {
            try store.save(plistData: tamperedData)
        }
    }

    @Test("Plist without a Signature field is rejected as malformed")
    func missingSignatureRejected() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let dict: [String: Any] = [
            "Product": "Gargantua",
            "Email": "anyone@example.com",
        ]
        let bogus = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )

        #expect(throws: LicenseStoreError.malformedReceipt) {
            try store.save(plistData: bogus)
        }
    }

    @Test("Garbage bytes are rejected as malformed")
    func garbageRejected() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        let garbage = Data("definitely not a plist".utf8)

        #expect(throws: LicenseStoreError.malformedReceipt) {
            try store.save(plistData: garbage)
        }
    }

    @Test("Receipt accepts arbitrary AquaticPrime field sets")
    func arbitraryFieldsAccepted() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        // Minimal: just Product + a custom field
        let plistData = try TestKeys.signedLicensePlist(fields: [
            "Product": "Gargantua",
            "Whatever": "FastSpring might decide to include",
        ])

        let saved = try store.save(plistData: plistData)
        #expect(saved.product == "Gargantua")
        #expect(saved.fields["Whatever"] == "FastSpring might decide to include")
        #expect(saved.email == nil)
    }

    @Test("Loading from a license file URL works")
    func loadFromFileURL() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gargantualicense")
        let storeURL = tempFileURL()
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: storeURL)
        }
        let plistData = try TestKeys.signedLicensePlist()
        try plistData.write(to: sourceURL)

        let store = makeStore(at: storeURL)
        let receipt = try store.save(fileURL: sourceURL)
        #expect(receipt.email == "test@example.com")
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("Clear removes the saved license file")
    func clearRemovesFile() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url)
        try store.save(plistData: try TestKeys.signedLicensePlist())
        #expect(FileManager.default.fileExists(atPath: url.path))

        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.loadValidReceipt() == nil)
    }
}
