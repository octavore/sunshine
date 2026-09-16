import Foundation

/// A breadcrumb written to disk immediately before an install swap begins, so a future
/// launch can detect (and, in later versions, recover from) a process that died mid-swap.
struct PendingInstallMarker: Codable {
  let installURL: URL
  let oldAsidePath: URL
  let newBundlePath: URL
  let releaseTag: String
  let startedAt: Date

  static func markerURL(forBundleIdentifier bundleIdentifier: String) -> URL {
    SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("pending-install.plist")
  }

  func write(to url: URL) throws {
    let encoder = PropertyListEncoder()
    let data = try encoder.encode(self)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  static func read(from url: URL) -> PendingInstallMarker? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? PropertyListDecoder().decode(PendingInstallMarker.self, from: data)
  }

  static func remove(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
}

enum SunshineCache {
  private static let allowedComponentCharacters = CharacterSet.alphanumerics
    .union(CharacterSet(charactersIn: "-._"))

  /// Reduces server-supplied text to a single safe filename component. Release tags and
  /// asset names both reach the filesystem, and a git tag may legally contain "/"
  /// ("release/1.0"), which would otherwise nest a directory or escape the cache. Any
  /// character outside `[A-Za-z0-9-._]` becomes "_", and a component made only of dots
  /// references a directory rather than naming one, so it becomes "_" too.
  static func safeComponent(_ name: String) -> String {
    let mapped = String(
      name.unicodeScalars.map {
        allowedComponentCharacters.contains($0) ? Character($0) : "_"
      })
    // Filenames are capped well below the 255-byte limit; tags and asset names are
    // far shorter in practice.
    let truncated = String(mapped.prefix(120))
    if truncated.isEmpty || truncated.allSatisfy({ $0 == "." }) { return "_" }
    return truncated
  }

  static func directory(forBundleIdentifier bundleIdentifier: String) -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent(
      "Sunshine", isDirectory: true)
  }

  static func updateDirectory(forBundleIdentifier bundleIdentifier: String, releaseTag: String)
    -> URL
  {
    directory(forBundleIdentifier: bundleIdentifier)
      .appendingPathComponent("updates", isDirectory: true)
      .appendingPathComponent(safeComponent(releaseTag), isDirectory: true)
  }
}
