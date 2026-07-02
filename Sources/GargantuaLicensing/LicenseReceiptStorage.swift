import Foundation
import Security

/// Where the encoded activation receipt lives. The keychain implementation is
/// the production store — unlike the old plain `license.json`, its payload
/// can't be forged with a text editor. In-memory backs the tests.
public protocol LicenseReceiptStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

/// One-shot marker so the legacy `license.json` is only trusted on the first
/// launch after upgrading to keychain storage. Without it, dropping a forged
/// JSON file into Application Support would re-trigger "migration" and mint
/// licensed status.
public protocol LicenseMigrationMarker: Sendable {
    func isDone() -> Bool
    func markDone()
}

public final class UserDefaultsLicenseMigrationMarker: LicenseMigrationMarker, @unchecked Sendable {
    public static let key = "com.gargantua.licensing.receiptMigrated"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isDone() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    public func markDone() {
        defaults.set(true, forKey: Self.key)
    }
}

public final class InMemoryLicenseMigrationMarker: LicenseMigrationMarker, @unchecked Sendable {
    private let lock = NSLock()
    private var done: Bool

    public init(done: Bool = false) {
        self.done = done
    }

    public func isDone() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    public func markDone() {
        lock.lock()
        defer { lock.unlock() }
        done = true
    }
}

/// Keychain-backed receipt storage, same shape as `KeychainCloudAPIKeyStore`
/// in GargantuaCore. Items are device-only and never sync
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); same-app access is
/// silent, so migration from `license.json` never prompts.
public struct KeychainLicenseReceiptStorage: LicenseReceiptStorage {
    private let service: String
    private let account: String

    public init(
        service: String = "com.gargantua.licensing",
        account: String = "polar-license-receipt"
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainLicenseStorageError(status: status)
        }
        return result as? Data
    }

    public func write(_ data: Data) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainLicenseStorageError(status: updateStatus)
        }

        let query = lookup.merging(attributes) { _, new in new }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainLicenseStorageError(status: status)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainLicenseStorageError(status: status)
        }
    }
}

public final class InMemoryLicenseReceiptStorage: LicenseReceiptStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    public init(initialData: Data? = nil) {
        self.stored = initialData
    }

    public func read() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        stored = data
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}

public struct KeychainLicenseStorageError: Error, LocalizedError, Equatable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain operation failed with status \(status)."
    }
}
