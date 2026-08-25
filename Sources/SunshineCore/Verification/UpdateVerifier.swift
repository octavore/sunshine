import Foundation

/// Verifies a downloaded update's authenticity using macOS code signing and notarization
/// instead of a separate signing key: the update must be signed by the same Team ID as
/// the running app, and (by default) pass Gatekeeper's notarization check. Every check
/// fails closed — an error or indeterminate result is treated as rejection.
public struct UpdateVerifier: Sendable {
    public var requireNotarization: Bool
    var checker: any CodeSigningChecking

    public init(requireNotarization: Bool = true, checker: any CodeSigningChecking = SystemCodeSigningChecker()) {
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
            throw SunshineError.verificationFailed(.teamIdentifierMismatch(expected: runningTeamID, found: candidateTeamID))
        }

        var notarizationAccepted: Bool?
        if requireNotarization {
            let accepted = checker.isNotarized(at: url)
            notarizationAccepted = accepted
            guard accepted else {
                throw SunshineError.verificationFailed(.notarizationRejected(reason: "Gatekeeper did not accept the downloaded bundle."))
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
