import Foundation

/// Persisted updater preferences for auto-check, auto-install, and prerelease channel.
/// Keys are scoped per bundle identifier, as in `SkipAndRemindStore`.
final class UpdatePreferencesStore {
  private let defaults: UserDefaults
  private let keyPrefix: String

  init(bundleIdentifier: String, defaults: UserDefaults = .standard) {
    self.keyPrefix = "com.sunshine.\(bundleIdentifier)."
    self.defaults = defaults
  }

  private var automaticallyCheckKey: String { keyPrefix + "automaticallyCheckForUpdates" }
  private var automationLevelKey: String { keyPrefix + "automationLevel" }
  private var allowPrereleasesKey: String { keyPrefix + "allowPrereleases" }

  var automaticallyCheckForUpdates: Bool? {
    get { defaults.object(forKey: automaticallyCheckKey) as? Bool }
    set { defaults.set(newValue, forKey: automaticallyCheckKey) }
  }

  var automationLevel: UpdateAutomationLevel? {
    get {
      switch defaults.string(forKey: automationLevelKey) {
      case "manual": return .manual
      case "autoDownload": return .autoDownload
      case "autoDownloadAndInstall": return .autoDownloadAndInstall
      default: return nil
      }
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: automationLevelKey)
        return
      }
      switch newValue {
      case .manual: defaults.set("manual", forKey: automationLevelKey)
      case .autoDownload: defaults.set("autoDownload", forKey: automationLevelKey)
      case .autoDownloadAndInstall:
        defaults.set("autoDownloadAndInstall", forKey: automationLevelKey)
      }
    }
  }

  var allowPrereleases: Bool? {
    get { defaults.object(forKey: allowPrereleasesKey) as? Bool }
    set { defaults.set(newValue, forKey: allowPrereleasesKey) }
  }
}
