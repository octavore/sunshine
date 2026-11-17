import Foundation

/// Reason an install location cannot be updated in place.
public enum InstallLocationIssue: Sendable, Equatable {
  /// App runs from a randomized read-only App Translocation path.
  case translocated
  /// App runs from a read-only volume such as a mounted disk image.
  case readOnlyVolume
}

public enum InstallLocationChecker {
  /// Reason the app at `appURL` is in a location that blocks updates, if any.
  /// Returns `nil` for ordinary locations. A writability failure alone is not reported here.
  public static func issue(for appURL: URL) -> InstallLocationIssue? {
    if appURL.path.contains("/AppTranslocation/") {
      return .translocated
    }
    let volumeIsReadOnly = try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
      .volumeIsReadOnly
    if volumeIsReadOnly == true {
      return .readOnlyVolume
    }
    return nil
  }

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
