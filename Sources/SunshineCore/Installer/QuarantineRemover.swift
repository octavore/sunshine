import Foundation

enum QuarantineRemover {
  private static let attributeName = "com.apple.quarantine"

  /// Remove `com.apple.quarantine` from every file in the bundle recursively.
  /// Call this only after verification succeeds. Gatekeeper and quarantine checks then
  /// stay fully active during the authenticity check.
  static func removeQuarantine(at url: URL) {
    removexattr(url.path, attributeName, XATTR_NOFOLLOW)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    else { return }
    for case let fileURL as URL in enumerator {
      removexattr(fileURL.path, attributeName, XATTR_NOFOLLOW)
    }
  }
}
