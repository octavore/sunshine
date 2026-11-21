import Foundation
import Sunshine

/// Owner and repo of the example app, matching the `ExampleData.updater` configuration.
/// They derive the `UserDefaults` key prefix that `SunshineUpdater` uses to persist state.
let exampleOwner = "example"
let exampleRepo = "example"

/// Adjustable settings of the "latest" release on the `Configuration` screen of the example
/// app.
/// They show how `UpdateIndicatorView` and other views react to different releases.
struct ExampleReleaseConfig: Hashable {
  var latestVersion: String = "2.1.0"
  var includeReleaseNotes: Bool = true
  var isPrerelease: Bool = false
  /// Make every release fetch fail, so the error state can be shown.
  var simulatesError: Bool = false
  /// Points the updater at a fake App Translocation path, so the move offer applies.
  var simulatesUnsuitableLocation: Bool = false
}

/// `ReleasesProviding` conformer whose fetches always fail.
struct FailingReleasesProvider: ReleasesProviding {
  /// Timeout error with the description `URLSession` attaches to real ones.
  private static let timeout = URLError(
    .timedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])

  func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
    throw SunshineError.network(underlying: Self.timeout)
  }

  func fetchRecentReleases(owner: String, repo: String) async throws -> [GitHubRelease] {
    throw SunshineError.network(underlying: Self.timeout)
  }
}

/// Sample release data and updaters without network access, for the view gallery of the
/// example app.
enum ExampleData {
  /// Fake App Translocation path. No app exists here.
  static let translocatedInstallLocation = URL(
    fileURLWithPath: "/private/var/folders/example/T/AppTranslocation/EXAMPLE/d/Example.app")

  /// `UserDefaults` key prefix that `SkipAndRemindStore` and `UpdatePreferencesStore` use
  /// to persist the updater state of this app.
  static var userDefaultsKeyPrefix: String {
    let bundleID = Bundle.main.bundleIdentifier ?? "\(exampleOwner).\(exampleRepo)"
    return "com.sunshine.\(bundleID)."
  }

  static let releaseNotes = """
    ## What's New

    - Faster launch times on Apple Silicon.
    - Fixed a crash when importing large files.
    - Redesigned the sidebar with collapsible sections.

    ### Notes
    This release also updates the bundled dependencies for security fixes.
    """

  static func release(
    tag: String, prerelease: Bool = false, daysAgo: Int = 1, includeNotes: Bool = true
  ) -> GitHubRelease {
    GitHubRelease(
      tagName: tag,
      name: tag,
      body: includeNotes ? releaseNotes : nil,
      draft: false,
      prerelease: prerelease,
      publishedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now),
      htmlURL: URL(string: "https://github.com/example/example/releases/tag/\(tag)"),
      assets: [
        GitHubAsset(
          name: "Example-\(tag).zip",
          browserDownloadURL: URL(
            string: "https://github.com/example/example/releases/download/\(tag)/Example.zip")!,
          size: 42_000_000,
          contentType: "application/zip"
        )
      ]
    )
  }

  static let releases: [GitHubRelease] = [
    release(tag: "2.1.0", daysAgo: 1),
    release(tag: "2.0.0", daysAgo: 30),
    release(tag: "1.9.0", daysAgo: 90),
  ]

  /// Fixed release list with the latest entry replaced by the settings in `config`.
  static func releases(for config: ExampleReleaseConfig) -> [GitHubRelease] {
    [
      release(
        tag: config.latestVersion, prerelease: config.isPrerelease, daysAgo: 1,
        includeNotes: config.includeReleaseNotes)
    ]
      + releases.dropFirst()
  }

  /// `SunshineUpdater` backed by `StaticReleasesProvider`, without network access.
  /// The example app always shows the same fixed release data.
  @MainActor
  static func updater(config: ExampleReleaseConfig = ExampleReleaseConfig()) -> SunshineUpdater {
    let provider: any ReleasesProviding =
      config.simulatesError
      ? FailingReleasesProvider()
      : StaticReleasesProvider(releases: releases(for: config))
    return SunshineUpdater(
      configuration: SunshineConfiguration(
        owner: exampleOwner, repo: exampleRepo,
        installLocation: config.simulatesUnsuitableLocation ? Self.translocatedInstallLocation : nil
      ),
      releasesProvider: provider
    )
  }
}
