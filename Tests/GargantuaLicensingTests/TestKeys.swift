import Foundation
import Security
@testable import GargantuaLicensing

enum TestKeys {
    static let developmentPublicKeyDERBase64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsV05CEZ5EF2S1gaWeHoU" +
        "3VOl2xAm07EOYmNDjc1klIGAxl4fBhUJgZzjfz3G3bLR5BpvzPVxrnBXoqnfFTU2" +
        "WJcU/AEkjedT6fpj4A0gaT6n+6GPAGX+btUt838U10472AuFAdNBRHwJkH1uKl5U" +
        "2u3u6ts+PnHKrocWoTQyAYTloq6voJQERdGK1Yat3QPS2KxqgQr/DV8Y8XBuG4WA" +
        "TEKoDWuMJOA/44VOFrFgGciDId07v6spzNlU8tpuaSo16Y5k0WzJzU25LAA1Q4OT" +
        "J2bmHrvBNsus7D2iAgFYpSZIIJV+RIfjx+0gX9eiTmgIhT+bAgfzaMp6r2zIulCh" +
        "iwIDAQAB"

    static let developmentPrivateKeyPKCS1Base64 =
        "MIIEpAIBAAKCAQEAsV05CEZ5EF2S1gaWeHoU3VOl2xAm07EOYmNDjc1klIGAxl4f" +
        "BhUJgZzjfz3G3bLR5BpvzPVxrnBXoqnfFTU2WJcU/AEkjedT6fpj4A0gaT6n+6GP" +
        "AGX+btUt838U10472AuFAdNBRHwJkH1uKl5U2u3u6ts+PnHKrocWoTQyAYTloq6v" +
        "oJQERdGK1Yat3QPS2KxqgQr/DV8Y8XBuG4WATEKoDWuMJOA/44VOFrFgGciDId07" +
        "v6spzNlU8tpuaSo16Y5k0WzJzU25LAA1Q4OTJ2bmHrvBNsus7D2iAgFYpSZIIJV+" +
        "RIfjx+0gX9eiTmgIhT+bAgfzaMp6r2zIulChiwIDAQABAoIBAAQpfCqh2LpvfIAe" +
        "pHSysxjXtMP1ifiCwApc0PUbzxK33ULXN5XBdAX0hAqODRCFXzm7YxWlfT1Xyb6s" +
        "vmob49wW8FLSxgq5O6j5Prm/WE9DI9cBHT8Ocna9J7hkkL0isVkD02NN4H5QBaHV" +
        "4UcH2Q7pvkCibdn/FDLQ3OrIgK0anFxmgMlXREzr5bDhuolcA5kqSZ/7URqgBp1b" +
        "ak8yHdJCshHRgqjFuXPXxyCv+Hs5QbI/JdI0TzABiPxO2hTPY6W32NID+R2OQclP" +
        "yOeOXuAuA2DlisyGqbO9niDS/QIkHCI9FexNcupMy3rtv0v2ox1picX/06v6Phgp" +
        "D2BVzt0CgYEA2jWMCkY6qBFPhtRbKHeKim2xTjN5WRwnkRB0Hel8Jpka4/d4ly6J" +
        "qkfbNY5tnIIoc/yENARRDEoMjQps+8WqD8HcRY3IVZSjx4GlkP7St1tCstclm25y" +
        "SKJByEXEra7BM+Lh8hGg58qm+Gs+C9fckskVLkYBdfgihmvcLm46WE0CgYEA0BTI" +
        "sVSuNwlPythvDRjgchYjYQotvafrVcbpsR+r7gUq8LpqZW0PjSyHugFILjHYRQdY" +
        "HrphqEUjm7SV3cMzGfgJ/YdknHM6tTqQVtcydapVx36hs2EiGv7oHQuJQEGZSQ0K" +
        "qbbcQuS8bgPPVWzRXEIf356UEdbPhsyAyGhazTcCgYEA0RU11jJsydWsafjYT/Ib" +
        "IYDxv4i64ZOEpg8p8+9hMmrJxV2+gr3o0ux/MtYCWVCuClUPJ/hq4GejlxFCVAyW" +
        "YvrSYSL1rmr6c5PaXRCOP3qGcm6Mbl5pywcOGSQgzHsCTQE8loIlt3QKgUXg8eAo" +
        "Tc23KduSUsMr8bkwBJ1B8pECgYBna30YTitMpW8oNYx0aQHdEk3BRGrZkaUw++1Y" +
        "oJI2ehEOlsic4qjRFOnctBhpBVMlc/IDS8WP+dUp5YZ7MzKp3JMylGGYNNlgC9yD" +
        "nO+yddeukKzT2Bo4aqt5DCvKaRBDs5yyH3W4NbHFyFT7c1tXTHJFFa8ocqiwqeH0" +
        "OZGv3wKBgQDZlg3nQRHXX1OsLPt5smC1AC3qmsbvzw7D6b2OHKC3vFHaqOBKCHOZ" +
        "vi1rbDdZRO8CDMX3N1vsM096fI7JXBlYRxNSQGYZ8A0TTUh4OybNHlCYcfWRjYR+" +
        "JPFi0hvby7zAGWhrfAXOwIHa4GTGzAtsK+e04feKhj488vJ0K33Y5g=="

    static var developmentPublicKeyDER: Data {
        // swiftlint:disable:next force_unwrapping
        Data(base64Encoded: developmentPublicKeyDERBase64, options: [.ignoreUnknownCharacters])!
    }

    static var developmentPublicKey: SecKey {
        // swiftlint:disable:next force_try
        try! LicenseSigningKeys.makePublicKey(from: developmentPublicKeyDER)
    }

    static var developmentPrivateKey: SecKey {
        // swiftlint:disable:next force_unwrapping
        let der = Data(base64Encoded: developmentPrivateKeyPKCS1Base64, options: [.ignoreUnknownCharacters])!
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        // swiftlint:disable:next force_unwrapping
        return SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error)!
    }

    /// Build an AquaticPrime-style XML plist signed with the dev private key.
    /// Mirrors what FastSpring emits for our product config.
    static func signedLicensePlist(
        fields: [String: String] = [
            "Product": "Gargantua",
            "Name": "Test User",
            "Email": "test@example.com",
            "Order": "TEST-ORDER-001",
            "Timestamp": "Thu, 28 May 2026 12:00:00 +0000",
        ]
    ) throws -> Data {
        // Canonical message = values sorted alphabetically by key, UTF-8 concatenated.
        var canonical = Data()
        for key in fields.keys.sorted() {
            // swiftlint:disable:next force_unwrapping
            canonical.append(Data(fields[key]!.utf8))
        }
        var error: Unmanaged<CFError>?
        guard let sigCF = SecKeyCreateSignature(
            developmentPrivateKey,
            .rsaSignatureMessagePKCS1v15SHA1,
            canonical as CFData,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? NSError(domain: "TestKeys", code: -1)
        }
        let signature = sigCF as Data

        var plist: [String: Any] = fields
        plist[LicenseReceipt.signatureKey] = signature
        return try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
    }
}
