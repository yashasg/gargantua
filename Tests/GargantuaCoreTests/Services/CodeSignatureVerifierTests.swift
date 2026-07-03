import Foundation
import Testing
@testable import GargantuaCore

@Suite("CodeSignatureVerifier")
struct CodeSignatureVerifierTests {

    // MARK: - CodeSignatureInfo model

    @Test("`.unknown` sentinel has nil valid and nil teamIdentifier")
    func unknownSentinel() {
        #expect(CodeSignatureInfo.unknown.valid == nil)
        #expect(CodeSignatureInfo.unknown.teamIdentifier == nil)
    }

    @Test("CodeSignatureInfo is Equatable across all field combinations")
    func equatable() {
        let a = CodeSignatureInfo(valid: true, teamIdentifier: "EQHXZ8M8AV")
        let b = CodeSignatureInfo(valid: true, teamIdentifier: "EQHXZ8M8AV")
        let c = CodeSignatureInfo(valid: true, teamIdentifier: "DIFFERENT")
        let d = CodeSignatureInfo(valid: false, teamIdentifier: "EQHXZ8M8AV")
        let e = CodeSignatureInfo(valid: nil, teamIdentifier: nil)

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        #expect(a != e)
        #expect(e == .unknown)
    }

    @Test("Invalid signatures are represented distinctly from unknown signatures")
    func invalidSignatureInfoIsDistinctFromUnknown() {
        let invalid = CodeSignatureInfo(valid: false, teamIdentifier: "TEAMID1234")

        #expect(invalid.valid == false)
        #expect(invalid.teamIdentifier == "TEAMID1234")
        #expect(invalid != .unknown)
    }

    // MARK: - DefaultCodeSignatureVerifier

    @Test("Apple-signed system binary verifies as valid")
    func appleSignedSystemBinaryVerifies() {
        // /bin/ls is shipped and signed by Apple on every macOS install.
        let url = URL(fileURLWithPath: "/bin/ls")
        let info = DefaultCodeSignatureVerifier().verify(bundleURL: url)
        #expect(info.valid == true)
    }

    @Test("Nonexistent path produces `.unknown`")
    func nonexistentPathIsUnknown() {
        let url = URL(fileURLWithPath: "/nonexistent/binary-\(UUID().uuidString)")
        let info = DefaultCodeSignatureVerifier().verify(bundleURL: url)
        #expect(info == .unknown)
    }

    @Test("Unsigned plain file (text) does not validate")
    func unsignedPlainFileDoesNotValidate() throws {
        // Create a plain text file in temp dir; SecStaticCode either fails to
        // create or fails to validate it. Either path is "not valid".
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeSignatureVerifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("plain.txt")
        try Data("not a binary".utf8).write(to: fileURL)

        let info = DefaultCodeSignatureVerifier().verify(bundleURL: fileURL)
        // Expectation: not validly signed. Either valid == false or .unknown.
        #expect(info.valid != true)
    }

    // MARK: - Resource-skip validation (identity must survive)

    @Test("Signing identity and Apple anchor survive resource-skip validation")
    func identitySurvivesResourceSkip() {
        // `/bin/ls` is Apple-signed on every install. Even though validation now
        // passes `kSecCSDoNotValidateResources`, the signature must still report
        // valid, the leaf CN (signing identity) must populate, and the
        // requirement-based anchor check must still resolve — those are exactly
        // the fields the trust UI reads.
        let details = DefaultCodeSignatureVerifier().verifyDetails(bundleURL: URL(fileURLWithPath: "/bin/ls"))
        #expect(details.valid == true)
        #expect(details.isAppleAnchor == true)
        #expect(details.signingIdentity != nil)
    }

    @Test("Executable tampering is still flagged invalid under resource-skip validation")
    func tamperedExecutableIsInvalid() throws {
        // Skipping *resource* hashing must not blind us to a modified
        // executable: the CodeDirectory still hashes the Mach-O code pages, so a
        // flipped code byte must break validity. Copy a signed system binary,
        // confirm the pristine copy validates, then corrupt it.
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: "/bin/ls")
        try #require(fileManager.fileExists(atPath: source.path))

        let tmpDir = fileManager.temporaryDirectory
            .appendingPathComponent("CodeSignatureVerifierTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tmpDir) }

        let copy = tmpDir.appendingPathComponent("ls")
        try fileManager.copyItem(at: source, to: copy)

        let verifier = DefaultCodeSignatureVerifier()
        // The embedded signature copies with the file, so the pristine copy
        // still validates — the precondition that makes the tamper meaningful.
        try #require(verifier.verify(bundleURL: copy).valid == true)

        var bytes = try Data(contentsOf: copy)
        try #require(bytes.count > 0x1000)
        // Corrupt everything past the fat/Mach-O header. A single byte flip can
        // land in inter-slice padding or a non-host architecture slice and go
        // unnoticed — only the host slice's code pages are hashed — so corrupt
        // broadly to guarantee we hit them regardless of fat layout.
        for index in 0x1000 ..< bytes.count {
            bytes[index] ^= 0xFF
        }
        try bytes.write(to: copy)

        #expect(verifier.verify(bundleURL: copy).valid != true,
                "A tampered executable must not report a valid signature")
    }
}
