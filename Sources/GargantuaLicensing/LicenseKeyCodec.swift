import Foundation

public enum LicenseKeyCodecError: Error, Sendable, Equatable {
    case malformedKey
}

/// Encodes/decodes the on-the-wire license key string that FastSpring (Phase 4)
/// will email customers. Format: base64url-encoded JSON of `LicenseReceipt`.
/// During Phase 3 dev, generate keys with `LicenseKeyCodec.encode(_:)` from the
/// test private key in `TestKeys.sign(_:)`.
public enum LicenseKeyCodec {
    public static func encode(_ receipt: LicenseReceipt) throws -> String {
        let json = try JSONEncoder().encode(receipt)
        return base64URLEncode(json)
    }

    public static func decode(_ keyString: String) throws -> LicenseReceipt {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = base64URLDecode(trimmed) else {
            throw LicenseKeyCodecError.malformedKey
        }
        do {
            return try JSONDecoder().decode(LicenseReceipt.self, from: data)
        } catch {
            throw LicenseKeyCodecError.malformedKey
        }
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: padded)
    }
}
