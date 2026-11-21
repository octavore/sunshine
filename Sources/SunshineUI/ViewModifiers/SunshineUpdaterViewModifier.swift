import SunshineCore
import SwiftUI

private struct SunshineUpdaterModifier: ViewModifier {
  @ObservedObject var controller: SunshineUpdaterUIController
  let appName: String
  let appIcon: Image?
  let style: SunshineUpdateUIStyle

  func body(content: Content) -> some View {
    content
      // Set the style synchronously on appear and not from a `task`. The style is then
      // in place before an early check can present a sheet.
      .onAppear { controller.updateUIStyle = style }
      .sheet(isPresented: $controller.isPresentingUpdateSheet) {
        if let message = controller.errorMessage {
          UpdateErrorView(message: message, releaseURL: controller.pendingUpdate?.htmlURL)
        } else {
          UpdateAvailableView(controller: controller, appName: appName, appIcon: appIcon)
            .interactiveDismissDisabled(controller.isInstalling)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if style == .cornerIndicator {
          UpdateIndicatorView(controller: controller, appName: appName, appIcon: appIcon)
            .padding(16)
        }
      }
      .alert(
        controller.skippedUpdate == nil ? "You're up to date!" : "Update Available",
        isPresented: $controller.isPresentingUpToDateAlert
      ) {
        if controller.skippedUpdate != nil {
          Button("View Update") { controller.viewSkippedUpdateTapped() }
        }
        Button("OK", role: .cancel) {}
      } message: {
        if let skippedUpdate = controller.skippedUpdate {
          Text(
            "The latest version of \(appName) is \(skippedUpdate.version.shortVersion). You have \(AppVersion.fromMainBundle().shortVersion)."
          )
        } else {
          Text(upToDateMessage(appName: appName, releaseURL: controller.upToDateReleaseURL))
        }
      }
  }

  /// Message "\(appName) \(version) is the latest version."
  /// The name and version link to the GitHub release page if it is known. The message is an
  /// `AttributedString` and not an interpolated Markdown string. An `appName` with
  /// Markdown characters then does not break parsing.
  private func upToDateMessage(appName: String, releaseURL: URL?) -> AttributedString {
    var linkRun = AttributedString("\(appName) \(AppVersion.fromMainBundle().shortVersion)")
    if let releaseURL {
      linkRun.link = releaseURL
    }
    return linkRun + AttributedString(" is the latest version.")
  }
}

extension View {
  /// Attach the ready-made Sunshine update UI.
  /// This is the minimal setup. Attach it once, near the root of your scene.
  /// `SunshineUpdater` starts the background check loop itself if `checkInterval` is
  /// configured, so the loop runs with or without this modifier.
  ///
  /// - Parameter style: `.sheet` (default) shows a modal as soon as an update is found.
  ///   `.cornerIndicator` shows a small badge in the bottom-trailing corner that the user
  ///   opens when ready. The design follows
  ///   https://mitchellh.com/writing/non-trivial-vibing.
  public func sunshineUpdater(
    _ controller: SunshineUpdaterUIController,
    appName: String = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "This app",
    appIcon: Image? = .fromMainBundle(),
    style: SunshineUpdateUIStyle = .sheet
  ) -> some View {
    modifier(
      SunshineUpdaterModifier(
        controller: controller, appName: appName, appIcon: appIcon, style: style))
  }
}
