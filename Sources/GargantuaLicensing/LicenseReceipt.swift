import Foundation

/// AquaticPrime-style license plist. FastSpring emits these as `.gargantualicense`
/// files at sale time, with arbitrary customer-info fields plus a `Signature` data
/// field. We verify the signature against the canonical form (all fields except
/// `Signature`, sorted by key, values concatenated as UTF-8 bytes) and accept
/// any field set the storefront chooses to send.
public struct LicenseReceipt: Sendable, Equatable {
    public static let signatureKey = "Signature"

    /// All license fields except `Signature`, as written by FastSpring. Keys
    /// commonly seen: `Name`, `Email`, `Product`, `Order`, `Timestamp`.
    public let fields: [String: String]

    /// Raw signature bytes extracted from the plist's `Signature` data entry.
    public let signature: Data

    public init(fields: [String: String], signature: Data) {
        self.fields = fields
        self.signature = signature
    }

    public var email: String? { fields["Email"] }
    public var name: String? { fields["Name"] }
    public var product: String? { fields["Product"] }
    public var order: String? { fields["Order"] }
    public var timestampString: String? { fields["Timestamp"] }

    /// Canonical message: values of non-signature fields, sorted alphabetically
    /// by key, concatenated as UTF-8 bytes. AquaticPrime spec, matches what
    /// FastSpring signs on the server side.
    public func canonicalMessage() -> Data {
        var data = Data()
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            data.append(Data(value.utf8))
        }
        return data
    }
}
