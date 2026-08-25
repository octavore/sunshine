import Foundation
import Security

enum CodeSignVerifier {
    struct SigningError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Validates the code signature at `url` (strict, deep, all architectures — equivalent
    /// to `codesign --verify --deep --strict`) and returns its Team ID, or throws if the
    /// signature itself is invalid.
    static func teamIdentifier(forSignedBundleAt url: URL) throws -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw SigningError(message: statusMessage(createStatus))
        }

        let flags: SecCSFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let validateStatus = SecStaticCodeCheckValidity(staticCode, flags, nil)
        guard validateStatus == errSecSuccess else {
            throw SigningError(message: statusMessage(validateStatus))
        }

        return try teamIdentifier(of: staticCode)
    }

    private static func teamIdentifier(of code: SecStaticCode) throws -> String? {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess, let info = information as? [String: Any] else {
            throw SigningError(message: statusMessage(status))
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Reads the Team ID of the currently running process, live, never from cached config.
    static func teamIdentifierOfRunningApp() throws -> String? {
        var selfCode: SecCode?
        let selfStatus = SecCodeCopySelf(SecCSFlags(), &selfCode)
        guard selfStatus == errSecSuccess, let selfCode else {
            throw SigningError(message: statusMessage(selfStatus))
        }
        var information: CFDictionary?
        // SecCode is toll-free castable to SecStaticCode at the C level; the Swift
        // overlay only exposes the SecStaticCode-typed overload.
        let staticSelfCode = unsafeBitCast(selfCode, to: SecStaticCode.self)
        let infoStatus = SecCodeCopySigningInformation(staticSelfCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            throw SigningError(message: statusMessage(infoStatus))
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Shells out to `spctl` since there is no public Security.framework symbol for
    /// notarization-ticket verification. Any failure to determine status returns `false`
    /// (fail closed — callers treat unknown as rejected when notarization is required).
    static func checkNotarization(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["-a", "-vv", "--type", "execute", url.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0 else { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("accepted") && output.contains("source=Notarized")
    }

    private static func statusMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}
