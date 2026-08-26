import Foundation

/// Anything that can produce GitHub release data for `SunshineUpdater`. `GitHubReleasesClient`
/// is the production conformer; `StaticReleasesProvider` supplies a fixed list instead, for
/// SwiftUI previews, examples, and tests that shouldn't hit the network.
public protocol ReleasesProviding: Sendable {
    func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease
    func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease]
}

extension GitHubReleasesClient: ReleasesProviding {
    public func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try await fetchRecentReleases(owner: owner, repo: repo, perPage: 10)
    }
}

/// A `ReleasesProviding` conformer backed by an explicit, fixed list of releases — no network
/// access. Pass one to `SunshineUpdater.init(configuration:releasesProvider:)` to drive
/// previews, examples, or tests against known release data.
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
