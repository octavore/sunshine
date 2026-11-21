import Foundation

/// Breadcrumb file written immediately before an install swap begins.
/// A later launch uses it to detect and recover from a process that died during the swap.
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

  /// Reduce server-supplied text to a single safe filename component.
  /// Release tags and asset names both reach the filesystem. A git tag can contain "/",
  /// as in "release/1.0", which would nest a directory or escape the cache. Any character
  /// outside `[A-Za-z0-9-._]` becomes "_". A component made only of dots refers to a
  /// directory and also becomes "_".
  static func safeComponent(_ name: String) -> String {
    let mapped = String(
      name.unicodeScalars.map {
        allowedComponentCharacters.contains($0) ? Character($0) : "_"
      })
    // Cap filenames well below the 255-byte limit. Tags and asset names are shorter in
    // practice.
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
