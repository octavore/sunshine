import Foundation

/// Abstraction over the actual codesign/notarization system calls, so `UpdateVerifier`'s
/// decision logic can be unit tested with canned results instead of real signed binaries.
public protocol CodeSigningChecking: Sendable {
  func validateSignature(at url: URL) throws -> String?  // returns Team ID, or throws on invalid signature
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
