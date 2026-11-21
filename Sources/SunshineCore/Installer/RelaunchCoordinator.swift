import Foundation

/// Paths and handshake shared by the host process and the relaunch script.
/// `RelaunchScript` performs the swap and relaunch. It is spawned detached so the host can
/// terminate normally first.
enum RelaunchCoordinator {
  static let relaunchArgumentPrefix = "--sunshine-relaunched-from="

  /// Sentinel file the relaunched app writes at startup.
  /// The script and the relaunched app derive this path from the same raw tag. Sanitizing
  /// happens only here. Otherwise the handshake does not match.
  static func sentinelURL(forBundleIdentifier bundleIdentifier: String, releaseTag: String) -> URL {
    SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("launched-ok-\(SunshineCache.safeComponent(releaseTag))")
  }

  static func scriptURL(forBundleIdentifier bundleIdentifier: String) -> URL {
    SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("relaunch.sh")
  }

  /// Abort file written by the host if termination is cancelled after the script spawns.
  /// The script polls for it and exits without changing anything.
  static func abortURL(forBundleIdentifier bundleIdentifier: String) -> URL {
    SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("install-aborted")
  }

  static func logURL(forBundleIdentifier bundleIdentifier: String) -> URL {
    SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("relaunch.log")
  }

  /// Confirm a pending relaunch handshake.
  /// Call this once, as early as possible in host app startup. UI and headless
  /// integrations both call it from `applicationDidFinishLaunching` or equivalent.
  ///
  /// - Parameter notifyOnSuccess: Matches `SunshineConfiguration.notifyOnSuccessfulUpdate`.
  ///   If `false`, the handshake still completes and no system notification is posted.
  static func confirmSuccessfulRelaunchIfNeeded(
    bundleIdentifier: String, notifyOnSuccess: Bool = true
  ) {
    guard
      let releaseTag = ProcessInfo.processInfo.arguments.first(where: {
        $0.hasPrefix(relaunchArgumentPrefix)
      })
    else {
      return
    }
    let tag = String(releaseTag.dropFirst(relaunchArgumentPrefix.count))
    let sentinel = sentinelURL(forBundleIdentifier: bundleIdentifier, releaseTag: tag)
    try? FileManager.default.createDirectory(
      at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: sentinel.path, contents: Data())
    if notifyOnSuccess {
      UpdateNotifications.updateInstalled(releaseTag: tag)
    }
  }

  /// Signal a waiting script to stand down.
  /// Used if host termination was cancelled after the script started.
  static func abortPendingInstall(bundleIdentifier: String) {
    let url = abortURL(forBundleIdentifier: bundleIdentifier)
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data())
  }

  /// Write the script and launch it under `/bin/sh`, fully detached.
  /// It inherits no stdio and is not awaited, so it outlives this process. Returns
  /// immediately after launch.
  static func spawn(_ plan: RelaunchPlan) throws {
    try RelaunchScript.write(to: plan.scriptURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = plan.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }
}
