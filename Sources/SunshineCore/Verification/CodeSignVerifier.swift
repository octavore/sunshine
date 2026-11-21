import Foundation
import Security

enum CodeSignVerifier {
  struct SigningError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
  }

  /// Validate the code signature at `url` and return its Team ID.
  /// Validation is strict, deep, and covers all architectures, like
  /// `codesign --verify --deep --strict`. Throws if the signature is invalid.
  static func teamIdentifier(forSignedBundleAt url: URL) throws -> String? {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard createStatus == errSecSuccess, let staticCode else {
      throw SigningError(message: statusMessage(createStatus))
    }

    let flags: SecCSFlags = SecCSFlags(
      rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
    let validateStatus = SecStaticCodeCheckValidity(staticCode, flags, nil)
    guard validateStatus == errSecSuccess else {
      throw SigningError(message: statusMessage(validateStatus))
    }

    return try teamIdentifier(of: staticCode)
  }

  private static func teamIdentifier(of code: SecStaticCode) throws -> String? {
    var information: CFDictionary?
    let status = SecCodeCopySigningInformation(
      code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    guard status == errSecSuccess, let info = information as? [String: Any] else {
      throw SigningError(message: statusMessage(status))
    }
    return info[kSecCodeInfoTeamIdentifier as String] as? String
  }

  /// Read the Team ID of the running process directly. It is not read from cached config.
  static func teamIdentifierOfRunningApp() throws -> String? {
    var selfCode: SecCode?
    let selfStatus = SecCodeCopySelf(SecCSFlags(), &selfCode)
    guard selfStatus == errSecSuccess, let selfCode else {
      throw SigningError(message: statusMessage(selfStatus))
    }
    var information: CFDictionary?
    // SecCode casts to SecStaticCode at the C level. The Swift overlay exposes only the
    // SecStaticCode overload.
    let staticSelfCode = unsafeBitCast(selfCode, to: SecStaticCode.self)
    let infoStatus = SecCodeCopySigningInformation(
      staticSelfCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
      throw SigningError(message: statusMessage(infoStatus))
    }
    return info[kSecCodeInfoTeamIdentifier as String] as? String
  }

  /// Check notarization with `spctl`.
  /// Security.framework has no public symbol for notarization ticket verification. Any
  /// failure to determine the status returns `false`. Callers treat an unknown status as
  /// rejected if notarization is required.
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
    let output =
      String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.contains("accepted") && output.contains("source=Notarized")
  }

  private static func statusMessage(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
      return message
    }
    return "OSStatus \(status)"
  }
}
