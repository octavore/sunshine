import Foundation
import UserNotifications

/// System notifications for update lifecycle events.
/// Each call requests authorization. If the user never granted it or declines, nothing is
/// posted and no error is reported.
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

  /// Posted once, on the first launch after a successful relaunch.
  static func updateInstalled(releaseTag: String) {
    post(
      title: "\(appName) updated", body: "\(releaseTag) is installed.",
      identifier: "sunshine-update-installed-\(releaseTag)")
  }

  /// Posted if a background check finds an update and `automationLevel` is `.manual`.
  /// Nothing downloads until the user acts.
  static func updateAvailable(releaseTag: String) {
    post(
      title: "\(appName) update available", body: "\(releaseTag) is ready to download.",
      identifier: "sunshine-update-available-\(releaseTag)")
  }

  /// Posted if an unattended download, verification, or install fails.
  /// The background check loop starts these. Foreground user actions do not.
  static func updateFailed(message: String) {
    post(
      title: "\(appName) update failed", body: message,
      identifier: "sunshine-update-failed-\(UUID().uuidString)")
  }
}
