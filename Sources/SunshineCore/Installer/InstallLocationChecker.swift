import Foundation

/// Reason an install location cannot be updated in place.
public enum InstallLocationIssue: Sendable, Equatable {
  /// App runs from a randomized read-only App Translocation path.
  case translocated
  /// App runs from a read-only volume such as a mounted disk image.
  case readOnlyVolume
}

public enum InstallLocationChecker {
  /// Reason the app at `appURL` is in a location that blocks updates.
  /// Returns `nil` for ordinary locations. A writability failure alone is not reported.
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

  /// Whether the current user can write to both the bundle and its parent directory.
  /// The move-aside and move-in swap requires write access to the parent directory, in
  /// addition to the bundle contents.
  public static func isWritable(_ appURL: URL) -> Bool {
    let fileManager = FileManager.default
    let parent = appURL.deletingLastPathComponent()
    return fileManager.isWritableFile(atPath: appURL.path)
      && fileManager.isWritableFile(atPath: parent.path)
  }
}
