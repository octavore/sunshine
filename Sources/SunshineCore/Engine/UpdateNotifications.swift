import Foundation
import UserNotifications

/// The system notifications this package can post for update lifecycle events. Each
/// call requests authorization; if the host has never granted it, or declines, nothing
/// is posted and the failure is silent, since a missed notification is not worth
/// surfacing as an error of its own.
enum UpdateNotifications {
  private static var appName: String {
    Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
  }

  private static func post(title: String, body: String, identifier: String) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  /// Fired once, on the first launch after a successful relaunch.
  static func updateInstalled(releaseTag: String) {
    post(
      title: "\(appName) updated", body: "\(releaseTag) is installed.",
      identifier: "sunshine-update-installed-\(releaseTag)")
  }

  /// Fired when a background check finds an update but `automationLevel` is `.manual`,
  /// so nothing downloads until the host app is brought to the foreground.
  static func updateAvailable(releaseTag: String) {
    post(
      title: "\(appName) update available", body: "\(releaseTag) is ready to download.",
      identifier: "sunshine-update-available-\(releaseTag)")
  }

  /// Fired when an unattended download/verify/install (triggered by the background
  /// check loop, not a foreground user action) fails.
  static func updateFailed(message: String) {
    post(
      title: "\(appName) update failed", body: message,
      identifier: "sunshine-update-failed-\(UUID().uuidString)")
  }
}
