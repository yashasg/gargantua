import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("License activation")
struct LicenseActivateTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-activate-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
    }

    @Test("LicenseKeyCodec round-trips a signed receipt")
    func keyCodecRoundTrips() throws {
        let receipt = try TestKeys.validReceipt(email: "round@trip.com")
        let keyString = try LicenseKeyCodec.encode(receipt)
        let decoded = try LicenseKeyCodec.decode(keyString)
        #expect(decoded == receipt)
    }

    @Test("Garbage key string throws malformedKey")
    func garbageKeyThrows() {
        #expect(throws: LicenseKeyCodecError.malformedKey) {
            try LicenseKeyCodec.decode("not a real key!!!")
        }
    }

    @Test("activate(keyString:) persists and reloads a valid key")
    func activatePersistsValidKey() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LicenseStore(
            fileURL: url,
            publicKey: LicenseSigningKeys.developmentPublicKey
        )
        let receipt = try TestKeys.validReceipt(email: "buyer@example.com")
        let keyString = try LicenseKeyCodec.encode(receipt)

        let activated = try store.activate(keyString: keyString)
        #expect(activated == receipt)
        #expect(store.loadValidReceipt() == receipt)
    }

    @Test("activate rejects a key whose signature was forged for a different public key")
    func activateRejectsForgedSignature() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LicenseStore(
            fileURL: url,
            publicKey: LicenseSigningKeys.developmentPublicKey
        )
        // Receipt with valid-shape but invalid signature
        let bogus = LicenseReceipt(
            email: "x@y.com",
            name: "Z",
            activatedAt: Date(timeIntervalSince1970: 0),
            signatureBase64: Data(repeating: 0x42, count: 64).base64EncodedString()
        )
        let keyString = try LicenseKeyCodec.encode(bogus)

        #expect(throws: LicenseStoreError.invalidSignature) {
            try store.activate(keyString: keyString)
        }
    }
}
