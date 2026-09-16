import Foundation

public enum UpdateAutomationLevel: Sendable, Equatable {
  /// Only surfaces `.updateAvailable`; the caller drives download/verify/install explicitly.
  case manual
  /// Downloads and verifies automatically, but pauses at `.readyToInstall` for confirmation.
  case autoDownload
  /// Runs the full check → download → verify → install pipeline unattended.
  case autoDownloadAndInstall
}

public struct SunshineConfiguration: Sendable {
  public var owner: String
  public var repo: String
  public var allowPrereleases: Bool
  public var assetMatcher: AssetMatching
  public var githubToken: String?
  /// Interval between automatic background checks. `nil` disables automatic checking
  /// (the host app must call `checkForUpdates()` itself).
  public var checkInterval: TimeInterval?
  /// Where the running app is installed. `nil` infers from `Bundle.main.bundleURL`.
  public var installLocation: URL?
  /// Require a passing Gatekeeper/notarization check in addition to a Team ID match.
  public var requireNotarization: Bool
  public var automationLevel: UpdateAutomationLevel

  public init(
    owner: String,
    repo: String,
    allowPrereleases: Bool = false,
    assetMatcher: AssetMatching = .zipOrDmgContainingApp(),
    githubToken: String? = nil,
    checkInterval: TimeInterval? = nil,
    installLocation: URL? = nil,
    requireNotarization: Bool = true,
    automationLevel: UpdateAutomationLevel = .manual
  ) {
    self.owner = owner
    self.repo = repo
    self.allowPrereleases = allowPrereleases
    self.assetMatcher = assetMatcher
    self.githubToken = githubToken
    self.checkInterval = checkInterval
    self.installLocation = installLocation
    self.requireNotarization = requireNotarization
    self.automationLevel = automationLevel
  }
}
