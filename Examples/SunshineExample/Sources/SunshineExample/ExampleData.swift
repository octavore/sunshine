import Foundation
import Sunshine

/// The example app's owner/repo, matching `ExampleData.updater`'s configuration — used to
/// derive the same `UserDefaults` key prefix `SunshineUpdater` persists its state under.
let exampleOwner = "example"
let exampleRepo = "example"

/// Adjustable knobs for the "latest" release the example app's `Configuration` screen lets
/// you tweak, so you can see how `UpdateIndicatorView` etc. react to different release shapes.
struct ExampleReleaseConfig: Hashable {
  var latestVersion: String = "2.1.0"
  var includeReleaseNotes: Bool = true
  var isPrerelease: Bool = false
}

/// Sample release data and network-free updaters for the example app's view gallery.
enum ExampleData {
  /// The `UserDefaults` key prefix `SkipAndRemindStore`/`UpdatePreferencesStore` persist
  /// this app's updater state under.
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

  /// The fixed release list, with the latest entry replaced by `config`'s settings.
  static func releases(for config: ExampleReleaseConfig) -> [GitHubRelease] {
    [
      release(
        tag: config.latestVersion, prerelease: config.isPrerelease, daysAgo: 1,
        includeNotes: config.includeReleaseNotes)
    ]
      + releases.dropFirst()
  }

  /// A `SunshineUpdater` backed by `StaticReleasesProvider` — no network access, so the
  /// example app always shows the same fixed release data.
  @MainActor
  static func updater(config: ExampleReleaseConfig = ExampleReleaseConfig()) -> SunshineUpdater {
    SunshineUpdater(
      configuration: SunshineConfiguration(owner: exampleOwner, repo: exampleRepo),
      releasesProvider: StaticReleasesProvider(releases: releases(for: config))
    )
  }
}
