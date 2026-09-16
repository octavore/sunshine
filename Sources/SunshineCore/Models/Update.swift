import Foundation

/// A normalized, update-check-ready representation of a GitHub release plus the asset
/// selected for this machine's architecture.
public struct Update: Sendable, Identifiable, Equatable {
  public let id: String  // release tag
  public let version: AppVersion
  /// Release notes for this release only. Use `SunshineUpdater` to obtain aggregated
  /// notes across any skipped intermediate versions.
  public let releaseNotesMarkdown: String?
  public let publishedAt: Date?
  public let htmlURL: URL?
  public let asset: GitHubAsset
  public let isPrerelease: Bool

  public init(release: GitHubRelease, asset: GitHubAsset) {
    self.id = release.tagName
    self.version = AppVersion(tag: release.tagName)
    self.releaseNotesMarkdown = release.body
    self.publishedAt = release.publishedAt
    self.htmlURL = release.htmlURL
    self.asset = asset
    self.isPrerelease = release.prerelease
  }
}
