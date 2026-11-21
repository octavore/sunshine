import Foundation

/// Verifier of downloaded update authenticity using macOS code signing and notarization.
/// There is no separate signing key. The same Team ID as the running app must sign the
/// update, and by default the update must pass Gatekeeper's notarization check. An error
/// or indeterminate result rejects the update.
public struct UpdateVerifier: Sendable {
  public var requireNotarization: Bool
  var checker: any CodeSigningChecking

  public init(
    requireNotarization: Bool = true, checker: any CodeSigningChecking = SystemCodeSigningChecker()
  ) {
    self.requireNotarization = requireNotarization
    self.checker = checker
  }

  public func verify(appAt url: URL) throws -> VerificationReport {
    let runningTeamID: String?
    do {
      runningTeamID = try checker.teamIdentifierOfRunningApp()
    } catch {
      throw SunshineError.verificationFailed(.runningAppUnsigned)
    }
    guard let runningTeamID else {
      throw SunshineError.verificationFailed(.runningAppUnsigned)
    }

    let candidateTeamID: String?
    do {
      candidateTeamID = try checker.validateSignature(at: url)
    } catch {
      throw SunshineError.verificationFailed(.signatureInvalid(message: "\(error)"))
    }

    guard let candidateTeamID else {
      throw SunshineError.verificationFailed(.teamIdentifierMissing)
    }

    guard candidateTeamID == runningTeamID else {
      throw SunshineError.verificationFailed(
        .teamIdentifierMismatch(expected: runningTeamID, found: candidateTeamID))
    }

    var notarizationAccepted: Bool?
    if requireNotarization {
      let accepted = checker.isNotarized(at: url)
      notarizationAccepted = accepted
      guard accepted else {
        throw SunshineError.verificationFailed(
          .notarizationRejected(reason: "Gatekeeper did not accept the downloaded bundle."))
      }
    }

    return VerificationReport(
      signatureValid: true,
      teamIdentifier: candidateTeamID,
      runningAppTeamIdentifier: runningTeamID,
      teamIdentifierMatches: true,
      notarizationAccepted: notarizationAccepted,
      details: "Signature valid, Team ID \(candidateTeamID) matches running app."
    )
  }
}
