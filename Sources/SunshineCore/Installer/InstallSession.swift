import Foundation

public struct VerifiedUpdate: Sendable {
  public let update: Update
  public let extractedAppURL: URL
  public let tempDirectory: URL
  public let verificationReport: VerificationReport
}

/// Install preparation that hands the swap to a detached shell script.
/// The script waits for this process to exit before changing anything. Nothing is moved
/// while the host is alive, so a host that fails to terminate leaves the installed bundle
/// unchanged.
struct InstallSession: Sendable {
  let bundleIdentifier: String
  let verifier: UpdateVerifier
  /// Spawn action. Tests replace it to inspect the plan without running a process.
  var spawn: @Sendable (RelaunchPlan) throws -> Void = RelaunchCoordinator.spawn

  /// Validate, stage, and spawn the relaunch script.
  /// Returns once the script is running and waiting. The caller then terminates the
  /// process. A throw means nothing was moved and the installed app is unchanged.
  func install(_ verified: VerifiedUpdate, installURL: URL) async throws {
    if let issue = InstallLocationChecker.issue(for: installURL) {
      throw SunshineError.installLocationUnsuitable(installURL, issue)
    }
    guard InstallLocationChecker.isWritable(installURL) else {
      throw SunshineError.installLocationNotWritable(installURL)
    }

    // Re-verify immediately before commit. The user can wait long between "ready to
    // install" and confirming.
    _ = try verifier.verify(appAt: verified.extractedAppURL)

    let asideURL = installURL.deletingLastPathComponent()
      .appendingPathComponent(
        ".\(installURL.deletingPathExtension().lastPathComponent) (old, \(Int(Date().timeIntervalSince1970))).app"
      )

    // Remove quarantine here and not in the script. The staged bundle is already verified.
    // The script does not need to run `xattr`.
    QuarantineRemover.removeQuarantine(at: verified.extractedAppURL)

    let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier)
    let marker = PendingInstallMarker(
      installURL: installURL,
      oldAsidePath: asideURL,
      newBundlePath: verified.extractedAppURL,
      releaseTag: verified.update.id,
      startedAt: Date()
    )
    // A write failure aborts the install. Without the marker, the next launch cannot
    // restore the bundle if the script dies during the swap.
    try marker.write(to: markerURL)

    let sentinelURL = RelaunchCoordinator.sentinelURL(
      forBundleIdentifier: bundleIdentifier, releaseTag: verified.update.id)
    let abortURL = RelaunchCoordinator.abortURL(forBundleIdentifier: bundleIdentifier)
    // Remove old files. A sentinel from an earlier install could confirm a reinstall of
    // the same tag. An abort file from an earlier cancelled install could cancel this one.
    try? FileManager.default.removeItem(at: sentinelURL)
    try? FileManager.default.removeItem(at: abortURL)

    let plan = RelaunchPlan(
      scriptURL: RelaunchCoordinator.scriptURL(forBundleIdentifier: bundleIdentifier),
      hostProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
      installURL: installURL,
      asideURL: asideURL,
      stagedURL: verified.extractedAppURL,
      sentinelURL: sentinelURL,
      markerURL: markerURL,
      abortURL: abortURL,
      logURL: RelaunchCoordinator.logURL(forBundleIdentifier: bundleIdentifier),
      releaseTag: verified.update.id
    )

    do {
      try spawn(plan)
    } catch {
      PendingInstallMarker.remove(at: markerURL)
      throw SunshineError.relaunchFailed(underlying: error)
    }
  }

  /// Finish a swap whose script died partway through.
  /// If the installed bundle is gone and the aside copy from the recorded install exists,
  /// move it back. Runs at `SunshineUpdater` init, before the stale aside sweep.
  static func recoverInterruptedInstall(bundleIdentifier: String) {
    let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier)
    guard let marker = PendingInstallMarker.read(from: markerURL) else { return }

    let fileManager = FileManager.default
    let installed = fileManager.fileExists(atPath: marker.installURL.path)
    let aside = fileManager.fileExists(atPath: marker.oldAsidePath.path)

    if !installed && aside {
      try? fileManager.moveItem(at: marker.oldAsidePath, to: marker.installURL)
    } else if installed && aside {
      // The swap completed and cleanup did not. The aside copy is no longer needed.
      try? fileManager.removeItem(at: marker.oldAsidePath)
    }

    PendingInstallMarker.remove(at: markerURL)
  }

  /// Best-effort cleanup of aside bundles left by an interrupted install.
  /// Runs at each `SunshineUpdater` init, so failed or aborted updates do not accumulate
  /// disk usage.
  static func sweepStaleAsideBundles(
    near installURL: URL, olderThan interval: TimeInterval = 24 * 60 * 60
  ) {
    let parent = installURL.deletingLastPathComponent()
    let prefix = ".\(installURL.deletingPathExtension().lastPathComponent) (old, "
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: parent, includingPropertiesForKeys: [.contentModificationDateKey]
      )
    else { return }

    let cutoff = Date().addingTimeInterval(-interval)
    for url in contents where url.lastPathComponent.hasPrefix(prefix) {
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      if let modified, modified < cutoff {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }
}
