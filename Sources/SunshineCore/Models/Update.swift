import Foundation

/// Normalized GitHub release with the asset selected for this machine's architecture.
public struct Update: Sendable, Identifiable, Equatable {
  /// Release tag.
  public let id: String
  public let version: AppVersion
  /// Release notes of this release only.
  /// `SunshineUpdater` provides notes aggregated across skipped intermediate versions.
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
