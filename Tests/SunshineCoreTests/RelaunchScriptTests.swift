import Foundation
import Testing

@testable import SunshineCore

/// Tests that run the real relaunch script under `/bin/sh` against fake bundles.
/// Stubs replace `open` and `pgrep`. The script performs the swap, the relaunch
/// handshake, and the rollback. These tests cover that behavior.
@Suite struct RelaunchScriptTests {
  /// Temporary layout used by every test, with the stubs the script calls.
  private struct Fixture {
    let root: URL
    let scriptURL: URL
    let installURL: URL
    let asideURL: URL
    let stagedURL: URL
    let sentinelURL: URL
    let markerURL: URL
    let abortURL: URL
    let logURL: URL
    let openLogURL: URL

    func read(_ appURL: URL) -> String? {
      try? String(contentsOf: appURL.appendingPathComponent("marker.txt"), encoding: .utf8)
    }

    var openInvocations: [String] {
      guard let contents = try? String(contentsOf: openLogURL, encoding: .utf8) else { return [] }
      return contents.split(separator: "\n").map(String.init)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
  }

  /// - Parameter relaunchSucceeds: Whether the stubbed `open` writes the sentinel the
  ///   script waits for. This is whether the new bundle confirmed its launch.
  private func makeFixture(relaunchSucceeds: Bool) throws -> Fixture {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "SunshineScript-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    let installDir = root.appendingPathComponent("Applications", isDirectory: true)
    try fileManager.createDirectory(at: installDir, withIntermediateDirectories: true)

    let installURL = installDir.appendingPathComponent("MyApp.app")
    let stagedURL = root.appendingPathComponent("staging/MyApp.app")
    for (url, marker) in [(installURL, "OLD"), (stagedURL, "NEW")] {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
      try marker.write(
        to: url.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    let sentinelURL = root.appendingPathComponent("launched-ok-v1.1.0")
    let openLogURL = root.appendingPathComponent("open-invocations.txt")

    let openStub = root.appendingPathComponent("open-stub.sh")
    let touchSentinel = relaunchSucceeds ? "touch \"\(sentinelURL.path)\"\n" : ""
    try """
    #!/bin/sh
    echo "$*" >>"\(openLogURL.path)"
    \(touchSentinel)exit 0
    """.write(to: openStub, atomically: true, encoding: .utf8)

    // Always reports no matching process. The fallback never accepts a failed handshake.
    let pgrepStub = root.appendingPathComponent("pgrep-stub.sh")
    try "#!/bin/sh\nexit 1\n".write(to: pgrepStub, atomically: true, encoding: .utf8)

    for stub in [openStub, pgrepStub] {
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    }

    let scriptURL = root.appendingPathComponent("relaunch.sh")
    try RelaunchScript.write(to: scriptURL)

    return Fixture(
      root: root,
      scriptURL: scriptURL,
      installURL: installURL,
      asideURL: installDir.appendingPathComponent(".MyApp (old, 1234).app"),
      stagedURL: stagedURL,
      sentinelURL: sentinelURL,
      markerURL: root.appendingPathComponent("pending-install.plist"),
      abortURL: root.appendingPathComponent("install-aborted"),
      logURL: root.appendingPathComponent("relaunch.log"),
      openLogURL: openLogURL
    )
  }

  /// - Parameter installPathOverride: Replaces the real install path to exercise the
  ///   absolute path guard of the script.
  @discardableResult
  private func run(
    _ fixture: Fixture,
    hostPID: String = "0",
    installPathOverride: String? = nil,
    openCommandOverride: String? = nil
  ) throws -> Int32 {
    let plan = RelaunchPlan(
      scriptURL: fixture.scriptURL,
      hostProcessIdentifier: Int32(hostPID) ?? 0,
      installURL: URL(fileURLWithPath: installPathOverride ?? fixture.installURL.path),
      asideURL: fixture.asideURL,
      stagedURL: fixture.stagedURL,
      sentinelURL: fixture.sentinelURL,
      markerURL: fixture.markerURL,
      abortURL: fixture.abortURL,
      logURL: fixture.logURL,
      releaseTag: "v1.1.0",
      openCommand: openCommandOverride ?? fixture.root.appendingPathComponent("open-stub.sh").path,
      pgrepCommand: fixture.root.appendingPathComponent("pgrep-stub.sh").path,
      sentinelTimeoutSeconds: 1
    )

    var arguments = plan.arguments
    // `URL(fileURLWithPath:)` normalizes the malformed paths that the guard rejects.
    // Substitute the override after the plan is built.
    if let installPathOverride {
      arguments[2] = installPathOverride
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = arguments
    // Hostile values. The script must ignore all of them.
    process.environment = [
      "PATH": "/nonexistent",
      "SUNSHINE_OPEN": "/bin/echo",
      "SUNSHINE_PGREP": "/usr/bin/true",
      "SUNSHINE_SENTINEL_TIMEOUT": "9999",
    ]
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }

  private func writeMarker(_ fixture: Fixture) throws {
    try Data("marker".utf8).write(to: fixture.markerURL)
  }

  @Test func confirmedRelaunchCommitsTheNewBundleAndCleansUp() throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeMarker(fixture)

    let status = try run(fixture)

    #expect(status == 0)
    #expect(fixture.read(fixture.installURL) == "NEW")
    #expect(!fixture.exists(fixture.asideURL))
    #expect(!fixture.exists(fixture.stagedURL))
    #expect(!fixture.exists(fixture.markerURL))
    #expect(!fixture.exists(fixture.scriptURL))  // The script deletes itself.
    #expect(fixture.openInvocations.count == 1)
    #expect(fixture.openInvocations[0].contains("--sunshine-relaunched-from=v1.1.0"))
  }

  @Test func unconfirmedRelaunchRollsBackAndReopensTheOldBundle() throws {
    let fixture = try makeFixture(relaunchSucceeds: false)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeMarker(fixture)

    let status = try run(fixture)

    #expect(status == 1)
    #expect(fixture.read(fixture.installURL) == "OLD")
    #expect(!fixture.exists(fixture.asideURL))
    #expect(!fixture.exists(fixture.markerURL))
    // One call launches the new bundle. One call launches the restored bundle.
    #expect(fixture.openInvocations.count == 2)
    #expect(!fixture.openInvocations[1].contains("--sunshine-relaunched-from"))
  }

  @Test func abortFileStandsTheScriptDownWhileTheHostIsStillAlive() throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeMarker(fixture)
    FileManager.default.createFile(atPath: fixture.abortURL.path, contents: Data())

    let host = Process()
    host.executableURL = URL(fileURLWithPath: "/bin/sh")
    host.arguments = ["-c", "sleep 5"]
    try host.run()
    defer { host.terminate() }

    let status = try run(fixture, hostPID: String(host.processIdentifier))

    #expect(status == 0)
    #expect(fixture.read(fixture.installURL) == "OLD")
    #expect(fixture.read(fixture.stagedURL) == "NEW")
    #expect(!fixture.exists(fixture.abortURL))
    #expect(!fixture.exists(fixture.markerURL))
    #expect(fixture.openInvocations.isEmpty)
  }

  /// A host that asks to cancel and then quits anyway has chosen the update by quitting.
  /// Honoring a stale abort file would leave the user on the old version without
  /// explanation.
  @Test func abortFileIsIgnoredOnceTheHostHasExited() throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeMarker(fixture)
    FileManager.default.createFile(atPath: fixture.abortURL.path, contents: Data())

    let status = try run(fixture)

    #expect(status == 0)
    #expect(fixture.read(fixture.installURL) == "NEW")
    #expect(!fixture.exists(fixture.abortURL))
    #expect(fixture.openInvocations.count == 1)
  }

  @Test(arguments: ["MyApp.app", "/", "/MyApp.app", "/Applications/MyApp", ""])
  func pathsThatAreNotAbsoluteAppBundlesAreRefused(_ installPath: String) throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let status = try run(fixture, installPathOverride: installPath)

    #expect(status == 1)
    #expect(fixture.read(fixture.installURL) == "OLD")
    #expect(fixture.read(fixture.stagedURL) == "NEW")
    #expect(fixture.openInvocations.isEmpty)
  }

  /// `run` sets SUNSHINE_OPEN to /bin/echo. That command writes no sentinel and no entry
  /// in the open log. A committed swap shows that the stub from the plan ran.
  @Test func environmentVariablesCannotRedirectTheCommandsTheScriptRuns() throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try writeMarker(fixture)

    let status = try run(fixture)

    #expect(status == 0)
    #expect(fixture.read(fixture.installURL) == "NEW")
    #expect(fixture.openInvocations.count == 1)
  }

  @Test(arguments: ["open", "usr/bin/open", ""])
  func relativeCommandPathsAreRefused(_ openCommand: String) throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let status = try run(fixture, openCommandOverride: openCommand)

    #expect(status == 1)
    #expect(fixture.read(fixture.installURL) == "OLD")
    #expect(fixture.read(fixture.stagedURL) == "NEW")
  }

  @Test func scriptWaitsForTheHostProcessToExit() throws {
    let fixture = try makeFixture(relaunchSucceeds: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let host = Process()
    host.executableURL = URL(fileURLWithPath: "/bin/sh")
    host.arguments = ["-c", "sleep 1"]
    try host.run()

    let started = Date()
    let status = try run(fixture, hostPID: String(host.processIdentifier))
    host.waitUntilExit()

    #expect(status == 0)
    #expect(Date().timeIntervalSince(started) >= 0.9)  // The swap did not start early.
    #expect(fixture.read(fixture.installURL) == "NEW")
  }
}
