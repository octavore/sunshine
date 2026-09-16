import Foundation
import Testing

@testable import SunshineCore

private struct MockChecker: CodeSigningChecking {
  var runningTeamID: String? = "TEAM123"
  var candidateTeamID: String? = "TEAM123"
  var signatureError: (any Error)?
  var runningError: (any Error)?
  var notarized: Bool = true

  func validateSignature(at url: URL) throws -> String? {
    if let signatureError { throw signatureError }
    return candidateTeamID
  }

  func teamIdentifierOfRunningApp() throws -> String? {
    if let runningError { throw runningError }
    return runningTeamID
  }

  func isNotarized(at url: URL) -> Bool { notarized }
}

private struct DummyError: Error {}

@Suite struct VerificationTests {
  let url = URL(fileURLWithPath: "/tmp/Fake.app")

  @Test func matchingTeamIDAndNotarizedPasses() throws {
    let verifier = UpdateVerifier(requireNotarization: true, checker: MockChecker())
    let report = try verifier.verify(appAt: url)
    #expect(report.teamIdentifierMatches)
    #expect(report.notarizationAccepted == true)
  }

  @Test func teamIDMismatchFails() {
    let verifier = UpdateVerifier(
      requireNotarization: true, checker: MockChecker(candidateTeamID: "OTHER"))
    #expect(throws: SunshineError.self) { try verifier.verify(appAt: url) }
  }

  @Test func unsignedCandidateFails() {
    let verifier = UpdateVerifier(
      requireNotarization: true, checker: MockChecker(candidateTeamID: nil))
    #expect(throws: SunshineError.self) { try verifier.verify(appAt: url) }
  }

  @Test func invalidSignatureFails() {
    let verifier = UpdateVerifier(
      requireNotarization: true, checker: MockChecker(signatureError: DummyError()))
    #expect(throws: SunshineError.self) { try verifier.verify(appAt: url) }
  }

  @Test func notarizationRequiredButUnavailableFailsClosed() {
    let verifier = UpdateVerifier(requireNotarization: true, checker: MockChecker(notarized: false))
    #expect(throws: SunshineError.self) { try verifier.verify(appAt: url) }
  }

  @Test func notarizationSkippedWhenNotRequired() throws {
    let verifier = UpdateVerifier(
      requireNotarization: false, checker: MockChecker(notarized: false))
    let report = try verifier.verify(appAt: url)
    #expect(report.teamIdentifierMatches)
  }

  @Test func unsignedRunningAppFails() {
    let verifier = UpdateVerifier(
      requireNotarization: true, checker: MockChecker(runningTeamID: nil))
    #expect(throws: SunshineError.self) { try verifier.verify(appAt: url) }
  }
}
