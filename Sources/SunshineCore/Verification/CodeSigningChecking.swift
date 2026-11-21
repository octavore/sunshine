import Foundation

/// Abstraction over the code signing and notarization system calls.
/// Unit tests of `UpdateVerifier` use canned results instead of signed binaries.
public protocol CodeSigningChecking: Sendable {
  /// Return the Team ID, or throw on an invalid signature.
  func validateSignature(at url: URL) throws -> String?
  func teamIdentifierOfRunningApp() throws -> String?
  func isNotarized(at url: URL) -> Bool
}

public struct SystemCodeSigningChecker: CodeSigningChecking {
  public init() {}

  public func validateSignature(at url: URL) throws -> String? {
    try CodeSignVerifier.teamIdentifier(forSignedBundleAt: url)
  }

  public func teamIdentifierOfRunningApp() throws -> String? {
    try CodeSignVerifier.teamIdentifierOfRunningApp()
  }

  public func isNotarized(at url: URL) -> Bool {
    CodeSignVerifier.checkNotarization(at: url)
  }
}
