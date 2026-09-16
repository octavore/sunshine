import Foundation

enum ArchiveExtractor {
  struct ExtractionError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
  }

  /// Extracts a downloaded `.zip` or `.dmg` asset and returns the URL of the single
  /// top-level `.app` bundle it contains.
  static func extractApp(fromArchiveAt archiveURL: URL, into destinationDirectory: URL) throws
    -> URL
  {
    try FileManager.default.createDirectory(
      at: destinationDirectory, withIntermediateDirectories: true)
    switch archiveURL.pathExtension.lowercased() {
    case "zip":
      return try extractZip(archiveURL, into: destinationDirectory)
    case "dmg":
      return try extractDMG(archiveURL, into: destinationDirectory)
    default:
      throw ExtractionError(message: "Unsupported archive format: \(archiveURL.pathExtension)")
    }
  }

  private static func extractZip(_ archiveURL: URL, into destinationDirectory: URL) throws -> URL {
    // `ditto` preserves bundle structure and extended attributes. It is
    // what Sparkle and Xcode use, and is more reliable than Foundation's zip APIs.
    try run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, destinationDirectory.path])
    return try findApp(in: destinationDirectory)
  }

  private static func extractDMG(_ archiveURL: URL, into destinationDirectory: URL) throws -> URL {
    let mountPoint = destinationDirectory.appendingPathComponent("mnt", isDirectory: true)
    try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
    try run(
      "/usr/bin/hdiutil",
      [
        "attach", archiveURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-readonly",
        "-quiet",
      ])
    defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) }

    let mountedApp = try findApp(in: mountPoint)
    let destinationApp = destinationDirectory.appendingPathComponent(mountedApp.lastPathComponent)
    try FileManager.default.copyItem(at: mountedApp, to: destinationApp)
    return destinationApp
  }

  private static func findApp(in directory: URL) throws -> URL {
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
      throw ExtractionError(message: "Archive did not contain a top-level .app bundle.")
    }
    return app
  }

  private static func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let message =
        String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "unknown error"
      throw ExtractionError(message: "\(executable) failed: \(message)")
    }
  }
}
