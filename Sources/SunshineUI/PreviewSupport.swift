#if DEBUG
  import Foundation
  import SunshineCore

  /// Sample data + a network-free `SunshineUpdater` for `#Preview`s across `SunshineUI`.
  /// Not part of the public API — built only in debug builds.
  enum PreviewSupport {
    static let releaseNotes = """
      ## What's New

      - Faster launch times on Apple Silicon.
      - Fixed a crash when importing large files.
      - Redesigned the sidebar with collapsible sections.

      ### Notes
      This release also updates the bundled dependencies for security fixes.
      """

    static func release(tag: String, name: String, prerelease: Bool = false, daysAgo: Int = 1)
      -> GitHubRelease
    {
      GitHubRelease(
        tagName: tag,
        name: name,
        body: releaseNotes,
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
      release(tag: "2.1.0", name: "2.1.0", daysAgo: 1),
      release(tag: "2.0.0", name: "2.0.0", daysAgo: 30),
      release(tag: "1.9.0", name: "1.9.0", daysAgo: 90),
    ]

    /// A `SunshineUpdater` backed by `StaticReleasesProvider`, so previews never hit the
    /// network. Callers should immediately trigger `checkForUpdates()` if they need
    /// `state`/`pendingUpdate` populated before rendering.
    @MainActor
    static func updater(releases: [GitHubRelease] = releases) -> SunshineUpdater {
      SunshineUpdater(
        configuration: SunshineConfiguration(owner: "example", repo: "example"),
        releasesProvider: StaticReleasesProvider(releases: releases)
      )
    }

    @MainActor
    static func controller(releases: [GitHubRelease] = releases) -> SunshineUpdaterUIController {
      let controller = SunshineUpdaterUIController(updater: updater(releases: releases))
      Task { await controller.updater.checkForUpdates() }
      return controller
    }
  }
#endif
