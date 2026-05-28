import Foundation
import Security

public enum LicenseStoreError: Error, Sendable, Equatable {
    case invalidSignature
    case malformedReceipt
    case fileIOFailed(String)
    case publicKeyUnavailable(String)
}

public final class LicenseStore: @unchecked Sendable {
    private let fileURL: URL
    private let publicKey: SecKey
    private let fileManager: FileManager
    private let lock = NSLock()

    public convenience init() {
        self.init(
            fileURL: LicenseStore.defaultFileURL,
            publicKey: LicenseSigningKeys.productionPublicKey
        )
    }

    public init(
        fileURL: URL,
        publicKey: SecKey,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.publicKey = publicKey
        self.fileManager = fileManager
    }

    public static var defaultFileURL: URL {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Gargantua", isDirectory: true)
        return supportDir.appendingPathComponent("license.gargantualicense", isDirectory: false)
    }

    public func loadValidReceipt() -> LicenseReceipt? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? parseAndVerify(plistData: data)
    }

    @discardableResult
    public func save(plistData: Data) throws -> LicenseReceipt {
        let receipt = try parseAndVerify(plistData: plistData)
        lock.lock()
        defer { lock.unlock() }
        let parent = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try plistData.write(to: fileURL, options: [.atomic])
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
        return receipt
    }

    /// Save from a license file URL — e.g., the `.gargantualicense` file the
    /// customer downloads from FastSpring. Reads, verifies, persists.
    @discardableResult
    public func save(fileURL source: URL) throws -> LicenseReceipt {
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
        return try save(plistData: data)
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw LicenseStoreError.fileIOFailed(error.localizedDescription)
        }
    }

    public func parseAndVerify(plistData: Data) throws -> LicenseReceipt {
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil
            )
        } catch {
            throw LicenseStoreError.malformedReceipt
        }
        guard let dict = raw as? [String: Any] else {
            throw LicenseStoreError.malformedReceipt
        }
        guard let signature = dict[LicenseReceipt.signatureKey] as? Data else {
            throw LicenseStoreError.malformedReceipt
        }

        // All non-signature fields, stringified, alphabetically sorted in the
        // canonical message. AquaticPrime tolerates any field set.
        var fields: [String: String] = [:]
        for (key, value) in dict where key != LicenseReceipt.signatureKey {
            if let s = value as? String {
                fields[key] = s
            } else if let n = value as? NSNumber {
                fields[key] = n.stringValue
            } else if let d = value as? Date {
                fields[key] = ISO8601DateFormatter().string(from: d)
            }
        }
        let receipt = LicenseReceipt(fields: fields, signature: signature)
        guard verify(receipt) else { throw LicenseStoreError.invalidSignature }
        return receipt
    }

    public func verify(_ receipt: LicenseReceipt) -> Bool {
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA1,
            receipt.canonicalMessage() as CFData,
            receipt.signature as CFData,
            &error
        )
        return isValid
    }
}
