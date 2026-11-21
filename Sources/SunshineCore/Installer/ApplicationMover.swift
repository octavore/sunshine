import AppKit
import Foundation

/// Copy of a running app bundle into an Applications folder, followed by a launch of the copy.
enum ApplicationMover {
  /// Candidate destination folders, in order of preference.
  static func defaultApplicationsDirectories() -> [URL] {
    [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true),
    ]
  }

  /// Destination for a copy of `appURL` in the first writable folder of `directories`.
  /// A missing folder is created. Returns `nil` if no folder is writable.
  static func destination(
    for appURL: URL, in directories: [URL] = defaultApplicationsDirectories()
  ) -> URL? {
    let fileManager = FileManager.default
    for directory in directories {
      if !fileManager.fileExists(atPath: directory.path) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      }
      if fileManager.isWritableFile(atPath: directory.path) {
        return directory.appendingPathComponent(appURL.lastPathComponent)
      }
    }
    return nil
  }

  /// Copy `appURL` into the first writable folder of `directories` and return the copy URL.
  /// Running instances of an existing bundle with the same name are quit, then the bundle is
  /// moved to the trash. The quarantine attribute is removed from the copy so it does not
  /// run translocated. Instances get `quitTimeout` seconds to quit before a force terminate.
  static func copy(
    appAt appURL: URL, into directories: [URL] = defaultApplicationsDirectories(),
    quitTimeout: TimeInterval = defaultQuitTimeout
  ) throws -> URL {
    guard let destination = destination(for: appURL, in: directories) else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destination.path) {
      quitRunningInstances(
        of: Bundle(url: appURL)?.bundleIdentifier, at: destination, timeout: quitTimeout)
      try fileManager.trashItem(at: destination, resultingItemURL: nil)
    }
    try fileManager.copyItem(at: appURL, to: destination)
    QuarantineRemover.removeQuarantine(at: destination)
    return destination
  }

  /// Default time to wait for a graceful quit before an instance is force terminated.
  static let defaultQuitTimeout: TimeInterval = 5

  /// Instances of `bundleIdentifier` running from `bundleURL`, excluding this process.
  static func runningInstances(of bundleIdentifier: String?, at bundleURL: URL)
    -> [NSRunningApplication]
  {
    guard let bundleIdentifier else { return [] }
    let target = bundleURL.resolvingSymlinksInPath()
    let current = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .filter { app in
        app.processIdentifier != current
          && app.bundleURL?.resolvingSymlinksInPath() == target
      }
  }

  /// Quit instances running from `bundleURL`. Each gets `terminate()`. Instances still
  /// running after `timeout` seconds get `forceTerminate()`.
  static func quitRunningInstances(
    of bundleIdentifier: String?, at bundleURL: URL, timeout: TimeInterval
  ) {
    let instances = runningInstances(of: bundleIdentifier, at: bundleURL)
    guard !instances.isEmpty else { return }
    for instance in instances { instance.terminate() }
    waitUntilTerminated(instances, timeout: timeout)
    for instance in instances where !instance.isTerminated { instance.forceTerminate() }
    waitUntilTerminated(instances, timeout: 1)
  }

  /// Spin the run loop until every instance has exited or `timeout` seconds pass.
  /// The run loop keeps running so that termination state updates on the main thread.
  private static func waitUntilTerminated(
    _ instances: [NSRunningApplication], timeout: TimeInterval
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while instances.contains(where: { !$0.isTerminated }), Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
  }

  /// Launch a new instance of the app at `url`.
  static func launch(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", url.path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }
}
