import Foundation
import Security

public enum LicenseSigningKeys {
    /// Production RSA-2048 public key used to verify AquaticPrime licenses
    /// emitted by FastSpring. The matching private key lives in FastSpring's
    /// product config (Gargantua → AquaticPrime fulfillment) and is never in
    /// this repo.
    ///
    /// SPKI X.509 SubjectPublicKeyInfo, DER-encoded, base64. SecKey loads
    /// either SPKI or raw PKCS#1; `makePublicKey(from:)` peels the SPKI header
    /// off the front when it sees one.
    public static let productionPublicKeyDERBase64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsqjeO2Ld7NRyPIsgdLO3" +
        "rBv6rU+5LhvUZiW2JT+qNPA2wWAQZ4bZZQausUEBJ94MH95oCpnJgnyd1gr04cNl" +
        "DlcY5UQUi6qXYSpWQrFb6mc+5X09xN7r/duEOXHhYc3eIVKnT9ITl1rKPkp+Rlly" +
        "5wfT0uOs5aUaaR3cH2Z/4VLacPS1zf0WX94BmckS8wUEP9HxJgy27/A2VAAKHPRc" +
        "Xiugmb0VAzLJyIDhSuMzOXDjPlZ1+stDRnNFxiqWNu3gr2pkDHlRLaQ1c8JLZuzt" +
        "sg65Qc4IVJCnfSyqjbrQoLU2Mcy6Zh/GqScq9X2Yqwxusvsb036IFhDuPKGGVoWE" +
        "3wIDAQAB"

    public static let productionPublicKeyDER: Data = Data(
        base64Encoded: productionPublicKeyDERBase64,
        options: [.ignoreUnknownCharacters]
    )!

    public static var productionPublicKey: SecKey {
        // swiftlint:disable:next force_try
        try! makePublicKey(from: productionPublicKeyDER)
    }

    public enum KeyError: Error, Sendable, Equatable {
        case unsupportedFormat
        case secKeyCreationFailed(String)
    }

    /// Construct a `SecKey` from either SPKI or raw PKCS#1 DER bytes.
    ///
    /// `SecKeyCreateWithData` only accepts raw PKCS#1 `RSAPublicKey`. The
    /// `openssl rsa -pubout` default output is SPKI (with a 24-byte ASN.1
    /// AlgorithmIdentifier header on RSA-2048), so we detect and strip it.
    public static func makePublicKey(from der: Data) throws -> SecKey {
        let pkcs1 = strippedSPKIHeader(der) ?? der
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw KeyError.secKeyCreationFailed(message)
        }
        return key
    }

    /// SPKI wraps the PKCS#1 RSAPublicKey in an AlgorithmIdentifier + BIT
    /// STRING. For RSA-2048 the prefix is a fixed 24-byte sequence; detect it
    /// to support either input format without callers having to know.
    private static func strippedSPKIHeader(_ der: Data) -> Data? {
        // SPKI prefix for RSA-2048: 30 82 LL LL 30 0D 06 09 2A 86 48 86 F7 0D 01 01 01 05 00 03 82 KK KK 00
        let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        guard der.count > 24, der.starts(with: [0x30, 0x82]) else { return nil }
        let oidSlice = der.dropFirst(6).prefix(rsaOID.count)
        guard Array(oidSlice) == rsaOID else { return nil }
        return der.dropFirst(24)
    }
}
