import Foundation

enum QuarantineRemover {
  private static let attributeName = "com.apple.quarantine"

  /// Recursively strips `com.apple.quarantine` from every file in the bundle. Must only
  /// be called after verification succeeds, never before, so Gatekeeper/quarantine
  /// machinery is fully active while the authenticity check runs.
  static func removeQuarantine(at url: URL) {
    removexattr(url.path, attributeName, XATTR_NOFOLLOW)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    else { return }
    for case let fileURL as URL in enumerator {
      removexattr(fileURL.path, attributeName, XATTR_NOFOLLOW)
    }
  }
}
