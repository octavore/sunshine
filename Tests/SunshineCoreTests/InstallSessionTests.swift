import Foundation
import Testing

@testable import SunshineCore

private struct PassingChecker: CodeSigningChecking {
  func validateSignature(at url: URL) throws -> String? { "TEAM123" }
  func teamIdentifierOfRunningApp() throws -> String? { "TEAM123" }
  func isNotarized(at url: URL) -> Bool { true }
}

@Suite struct InstallSessionTests {
  private func makeUpdate(tag: String = "v1.1.0") -> Update {
    let asset = GitHubAsset(
      name: "MyApp-1.1.0-arm64.zip", browserDownloadURL: URL(string: "https://example.com/a.zip")!,
      size: 1, contentType: nil)
    let release = GitHubRelease(
      tagName: tag, name: nil, body: "notes", draft: false, prerelease: false, publishedAt: nil,
      htmlURL: nil, assets: [asset])
    return Update(release: release, asset: asset)
  }

  /// Creates a fake "bundle" (just a directory with a .app extension and a marker
  /// file) — verification itself is mocked, so the bundle's contents don't need to be
  /// real code-signed binaries.
  private func makeFakeApp(at url: URL, marker: String) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try marker.write(
      to: url.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
  }

  private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SunshineTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func readMarker(at appURL: URL) -> String? {
    try? String(contentsOf: appURL.appendingPathComponent("marker.txt"), encoding: .utf8)
  }

  private func makeVerified(extractedAppURL: URL, tempDirectory: URL) -> VerifiedUpdate {
    VerifiedUpdate(
      update: makeUpdate(), extractedAppURL: extractedAppURL, tempDirectory: tempDirectory,
      verificationReport: VerificationReport(
        signatureValid: true, teamIdentifier: "TEAM123", runningAppTeamIdentifier: "TEAM123",
        teamIdentifierMatches: true, notarizationAccepted: true, details: "")
    )
  }

  @Test func installStagesTheSwapWithoutTouchingTheInstalledBundle() async throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let installDir = root.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
    let installURL = installDir.appendingPathComponent("MyApp.app")
    try makeFakeApp(at: installURL, marker: "OLD")

    let extractedURL = root.appendingPathComponent("staging/MyApp.app")
    try makeFakeApp(at: extractedURL, marker: "NEW")

    let verifier = UpdateVerifier(requireNotarization: true, checker: PassingChecker())
    let captured = Captured()
    var session = InstallSession(bundleIdentifier: "com.test.app", verifier: verifier)
    session.spawn = { captured.plan = $0 }
    defer {
      PendingInstallMarker.remove(
        at: PendingInstallMarker.markerURL(forBundleIdentifier: "com.test.app"))
    }

    try await session.install(
      makeVerified(extractedAppURL: extractedURL, tempDirectory: root), installURL: installURL)

    // Nothing moves while the host is alive, which is the whole point of the script.
    #expect(readMarker(at: installURL) == "OLD")
    #expect(readMarker(at: extractedURL) == "NEW")

    let plan = try #require(captured.plan)
    #expect(plan.installURL == installURL)
    #expect(plan.stagedURL == extractedURL)
    #expect(plan.releaseTag == "v1.1.0")
    #expect(plan.hostProcessIdentifier == ProcessInfo.processInfo.processIdentifier)
    #expect(plan.asideURL.lastPathComponent.hasPrefix(".MyApp (old, "))
    #expect(plan.arguments.count == 13)
    // The script must never resolve these two through the environment.
    #expect(plan.openCommand == "/usr/bin/open")
    #expect(plan.pgrepCommand == "/usr/bin/pgrep")
    #expect(FileManager.default.fileExists(atPath: plan.markerURL.path))
  }

  @Test func nonWritableInstallLocationIsRejectedWithoutSpawning() async throws {
    let root = try makeTempRoot()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Applications").path)
      try? FileManager.default.removeItem(at: root)
    }

    let installDir = root.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
    let installURL = installDir.appendingPathComponent("MyApp.app")
    try makeFakeApp(at: installURL, marker: "OLD")

    // Remove write permission on the parent directory so the swap's rename cannot
    // occur, matching a shared-machine /Applications scenario.
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: installDir.path)

    let extractedURL = root.appendingPathComponent("staging/MyApp.app")
    try makeFakeApp(at: extractedURL, marker: "NEW")

    let verifier = UpdateVerifier(requireNotarization: true, checker: PassingChecker())
    let captured = Captured()
    var session = InstallSession(bundleIdentifier: "com.test.app", verifier: verifier)
    session.spawn = { captured.plan = $0 }

    await #expect(throws: SunshineError.self) {
      try await session.install(
        self.makeVerified(extractedAppURL: extractedURL, tempDirectory: root),
        installURL: installURL)
    }

    #expect(captured.plan == nil)
    #expect(readMarker(at: installURL) == "OLD")  // untouched
  }

  @Test func recoveryRestoresTheAsideBundleWhenTheScriptDiedMidSwap() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let installURL = root.appendingPathComponent("MyApp.app")
    let asideURL = root.appendingPathComponent(".MyApp (old, 1234).app")
    try makeFakeApp(at: asideURL, marker: "OLD")

    let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: "com.test.recovery")
    defer { PendingInstallMarker.remove(at: markerURL) }
    try FileManager.default.createDirectory(
      at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PendingInstallMarker(
      installURL: installURL, oldAsidePath: asideURL,
      newBundlePath: root.appendingPathComponent("staged/MyApp.app"),
      releaseTag: "v1.1.0", startedAt: Date()
    ).write(to: markerURL)

    InstallSession.recoverInterruptedInstall(bundleIdentifier: "com.test.recovery")

    #expect(readMarker(at: installURL) == "OLD")
    #expect(!FileManager.default.fileExists(atPath: asideURL.path))
    #expect(!FileManager.default.fileExists(atPath: markerURL.path))
  }

  @Test func recoveryDropsTheAsideBundleWhenTheSwapAlreadyCompleted() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let installURL = root.appendingPathComponent("MyApp.app")
    let asideURL = root.appendingPathComponent(".MyApp (old, 1234).app")
    try makeFakeApp(at: installURL, marker: "NEW")
    try makeFakeApp(at: asideURL, marker: "OLD")

    let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: "com.test.recovery2")
    defer { PendingInstallMarker.remove(at: markerURL) }
    try FileManager.default.createDirectory(
      at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PendingInstallMarker(
      installURL: installURL, oldAsidePath: asideURL,
      newBundlePath: root.appendingPathComponent("staged/MyApp.app"),
      releaseTag: "v1.1.0", startedAt: Date()
    ).write(to: markerURL)

    InstallSession.recoverInterruptedInstall(bundleIdentifier: "com.test.recovery2")

    #expect(readMarker(at: installURL) == "NEW")
    #expect(!FileManager.default.fileExists(atPath: asideURL.path))
  }

  @Test func staleAsideBundlesAreSweptButRecentOnesAreKept() throws {
    let root = try makeTempRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let installDir = root.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
    let installURL = installDir.appendingPathComponent("MyApp.app")
    try makeFakeApp(at: installURL, marker: "CURRENT")

    let staleAside = installDir.appendingPathComponent(".MyApp (old, 1000000000).app")
    let recentAside = installDir.appendingPathComponent(".MyApp (old, 9999999999).app")
    try makeFakeApp(at: staleAside, marker: "STALE")
    try makeFakeApp(at: recentAside, marker: "RECENT")

    let oldDate = Date().addingTimeInterval(-48 * 60 * 60)
    try FileManager.default.setAttributes(
      [.modificationDate: oldDate], ofItemAtPath: staleAside.path)

    InstallSession.sweepStaleAsideBundles(near: installURL, olderThan: 24 * 60 * 60)

    #expect(!FileManager.default.fileExists(atPath: staleAside.path))
    #expect(FileManager.default.fileExists(atPath: recentAside.path))
  }
}

/// Reference box so the `@Sendable` spawn closure can hand a value back to the test.
private final class Captured: @unchecked Sendable {
  var plan: RelaunchPlan?
}
