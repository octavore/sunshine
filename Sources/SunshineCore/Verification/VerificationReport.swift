public enum VerificationFailure: Error, Sendable, CustomStringConvertible {
  case signatureInvalid(message: String)
  case teamIdentifierMismatch(expected: String?, found: String?)
  case teamIdentifierMissing
  case notarizationRejected(reason: String)
  case runningAppUnsigned

  public var description: String {
    switch self {
    case .signatureInvalid(let message):
      return "Code signature is invalid: \(message)"
    case .teamIdentifierMismatch(let expected, let found):
      return
        "Downloaded update's Team ID (\(found ?? "none")) does not match the running app's Team ID (\(expected ?? "none"))."
    case .teamIdentifierMissing:
      return "Downloaded update is not signed by an identified developer."
    case .notarizationRejected(let reason):
      return "Downloaded update failed Gatekeeper/notarization check: \(reason)"
    case .runningAppUnsigned:
      return
        "The running app itself has no Team ID to compare against; refusing to install any update."
    }
  }
}

public struct VerificationReport: Sendable {
  public let signatureValid: Bool
  public let teamIdentifier: String?
  public let runningAppTeamIdentifier: String?
  public let teamIdentifierMatches: Bool
  public let notarizationAccepted: Bool?
  public let details: String
}
