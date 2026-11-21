import Foundation

public enum UpdateAutomationLevel: Sendable, Equatable {
  /// Surface `.updateAvailable` only.
  /// The caller starts download, verification, and install explicitly.
  case manual
  /// Download and verify automatically.
  /// The pipeline pauses at `.readyToInstall` for confirmation.
  case autoDownload
  /// Run the full check, download, verify, and install pipeline unattended.
  case autoDownloadAndInstall
}

public struct SunshineConfiguration: Sendable {
  public var owner: String
  public var repo: String
  public var allowPrereleases: Bool
  public var assetMatcher: AssetMatching
  public var githubToken: String?
  /// Interval between automatic background checks.
  /// `nil` disables automatic checking. The host app then calls `checkForUpdates()` itself.
  public var checkInterval: TimeInterval?
  /// Install location of the running app. `nil` uses `Bundle.main.bundleURL`.
  public var installLocation: URL?
  /// Require a passing Gatekeeper and notarization check in addition to a Team ID match.
  public var requireNotarization: Bool
  public var automationLevel: UpdateAutomationLevel
  /// Post a system notification on the first launch after a successful update.
  public var notifyOnSuccessfulUpdate: Bool
  /// Post a system notification if a background check finds an update and
  /// `automationLevel` is `.manual`.
  /// Without it, the update stays unseen until the host app is in the foreground. This has
  /// no effect on a check the host app starts, or if `checkInterval` is `nil`.
  public var notifyOnUpdateAvailable: Bool
  /// Post a system notification if an unattended download, verification, or install fails.
  /// The background check loop runs these. This has no effect on a failure from a
  /// foreground user action.
  public var notifyOnUpdateFailure: Bool

  public init(
    owner: String,
    repo: String,
    allowPrereleases: Bool = false,
    assetMatcher: AssetMatching = .zipOrDmgContainingApp(),
    githubToken: String? = nil,
    checkInterval: TimeInterval? = nil,
    installLocation: URL? = nil,
    requireNotarization: Bool = true,
    automationLevel: UpdateAutomationLevel = .manual,
    notifyOnSuccessfulUpdate: Bool = true,
    notifyOnUpdateAvailable: Bool = true,
    notifyOnUpdateFailure: Bool = true
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
    self.notifyOnSuccessfulUpdate = notifyOnSuccessfulUpdate
    self.notifyOnUpdateAvailable = notifyOnUpdateAvailable
    self.notifyOnUpdateFailure = notifyOnUpdateFailure
  }
}
