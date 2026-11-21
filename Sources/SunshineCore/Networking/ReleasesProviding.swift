import Foundation

/// Source of GitHub release data for `SunshineUpdater`.
/// `GitHubReleasesClient` is the production conformer. `StaticReleasesProvider` supplies a
/// fixed list for SwiftUI previews, examples, and tests that must not use the network.
public protocol ReleasesProviding: Sendable {
  func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease
  func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease]
}

extension GitHubReleasesClient: ReleasesProviding {
  public func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
    try await fetchRecentReleases(owner: owner, repo: repo, perPage: 10)
  }
}

/// `ReleasesProviding` conformer backed by a fixed list of releases, without network access.
/// Pass one to `SunshineUpdater.init(configuration:releasesProvider:)` to run previews,
/// examples, or tests against known release data.
public struct StaticReleasesProvider: ReleasesProviding {
  public var releases: [GitHubRelease]

  public init(releases: [GitHubRelease]) {
    self.releases = releases
  }

  public func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
    guard let latest = releases.first(where: { !$0.draft && !$0.prerelease }) else {
      throw SunshineError.network(underlying: URLError(.fileDoesNotExist))
    }
    return latest
  }

  public func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
    releases
  }
}
