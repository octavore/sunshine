import Foundation

/// Copies a running app bundle into an Applications folder and launches the copy.
enum ApplicationMover {
  /// Candidate destination folders, in order of preference.
  static func defaultApplicationsDirectories() -> [URL] {
    [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true),
    ]
  }

  /// Copy `appURL` into the first writable folder of `directories` and return the copy's URL.
  /// An existing bundle with the same name is moved to the trash first. The quarantine
  /// attribute is removed from the copy so it does not run translocated.
  static func copy(
    appAt appURL: URL, into directories: [URL] = defaultApplicationsDirectories()
  ) throws -> URL {
    let fileManager = FileManager.default
    for directory in directories {
      if !fileManager.fileExists(atPath: directory.path) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      }
      guard fileManager.isWritableFile(atPath: directory.path) else { continue }

      let destination = directory.appendingPathComponent(appURL.lastPathComponent)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.trashItem(at: destination, resultingItemURL: nil)
      }
      try fileManager.copyItem(at: appURL, to: destination)
      QuarantineRemover.removeQuarantine(at: destination)
      return destination
    }
    throw CocoaError(.fileWriteNoPermission)
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
