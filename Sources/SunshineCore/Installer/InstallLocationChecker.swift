import Foundation

public enum InstallLocationChecker {
  /// True only if both the bundle itself and its parent directory are writable by the
  /// current user. Parent-directory write access is required to perform the
  /// move-aside/move-in swap, not just write access to the bundle's contents.
  public static func isWritable(_ appURL: URL) -> Bool {
    let fileManager = FileManager.default
    let parent = appURL.deletingLastPathComponent()
    return fileManager.isWritableFile(atPath: appURL.path)
      && fileManager.isWritableFile(atPath: parent.path)
  }
}
