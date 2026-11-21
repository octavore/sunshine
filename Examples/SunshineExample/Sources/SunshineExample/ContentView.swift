import Foundation
import Sunshine
import SwiftUI

enum ExampleScreen: String, CaseIterable, Identifiable {
  case settings = "Settings"
  case updateAvailable = "Update Available"
  case updateIndicator = "Update Indicator"
  case updateError = "Update Error"
  case downloadProgress = "Download Progress"
  case configuration = "Configuration"
  case notifications = "Notifications"

  var id: String { rawValue }
}

struct ContentView: View {
  @State private var screen: ExampleScreen = .settings
  @State private var releaseConfig = ExampleReleaseConfig()

  var body: some View {
    NavigationSplitView {
      List(ExampleScreen.allCases, selection: $screen) { screen in
        Text(screen.rawValue).tag(screen)
      }
      .navigationSplitViewColumnWidth(200)
    } detail: {
      UpdaterHost(screen: screen, releaseConfig: $releaseConfig)
        .id(releaseConfig)
    }
    .frame(minWidth: 700, minHeight: 460)
  }
}

/// Holder of the `SunshineUpdater` and `SunshineUpdaterUIController` pair.
/// The pair is rebuilt if `ContentView` gives this view a new identity, see
/// `.id(releaseConfig)`. Changes on the `Configuration` screen then take effect.
private struct UpdaterHost: View {
  let screen: ExampleScreen
  @Binding var releaseConfig: ExampleReleaseConfig

  @StateObject private var updater: SunshineUpdater
  @StateObject private var controller: SunshineUpdaterUIController

  init(screen: ExampleScreen, releaseConfig: Binding<ExampleReleaseConfig>) {
    self.screen = screen
    self._releaseConfig = releaseConfig
    let updater = ExampleData.updater(config: releaseConfig.wrappedValue)
    _updater = StateObject(wrappedValue: updater)
    _controller = StateObject(wrappedValue: SunshineUpdaterUIController(updater: updater))
  }

  var body: some View {
    screenView
      .task { _ = await controller.updater.checkForUpdates() }
  }

  @ViewBuilder
  private var screenView: some View {
    switch screen {
    case .settings:
      SunshineUpdateSettingsView(controller: controller, appName: "Example App")
    case .updateAvailable:
      if controller.pendingUpdate != nil {
        UpdateAvailableView(controller: controller, appName: "Example App")
      } else {
        NoPendingUpdateView(controller: controller)
      }
    case .updateIndicator:
      ZStack(alignment: .bottomTrailing) {
        Color.clear
        if controller.pendingUpdate == nil && controller.errorMessage == nil {
          NoPendingUpdateView(controller: controller)
        }
        Toggle("Simulate Error", isOn: $releaseConfig.simulatesError)
          .padding(16)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        UpdateIndicatorView(controller: controller, appName: "Example App")
          .padding(16)
      }
    case .updateError:
      UpdateErrorView(
        message: "The GitHub API rate limit was exceeded. Try again after 5:00 PM.",
        releaseURL: URL(string: "https://github.com/example/example/releases/latest")
      )
    case .downloadProgress:
      DownloadProgressView(fractionComplete: 0.62) { controller.cancelDownloadTapped() }
    case .configuration:
      ExampleConfigurationView(controller: controller, appliedReleaseConfig: releaseConfig) {
        releaseConfig = $0
      }
    case .notifications:
      NotificationsTestView()
    }
  }
}

/// Screen that triggers all three system notifications of the package.
/// Each one requires a signed `.app` bundle with a bundle identifier, so macOS can authorize
/// and deliver the notification. Run this app with `strudel run`, not `swift run` or
/// `axo example`.
private struct NotificationsTestView: View {
  @State private var tag = "9.9.9-example"

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("1. Update Installed").font(.headline)
        Text(
          "Restarts this app with `--sunshine-relaunched-from=<tag>`, the same argument `RelaunchScript` passes for real once it has swapped the bundle. On the next launch, `SunshineUpdater.init` sees it and posts the notification (gated by `notifyOnSuccessfulUpdate`)."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        TextField("Release tag", text: $tag)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 240)
        Button("Simulate Update Relaunch") { simulateRelaunch(tag: tag) }
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("2. Update Available / 3. Update Failed").font(.headline)
        Text(
          "Both fire from the background check loop, not a foreground \"Check for Updates\" tap. On the Settings screen, turn on \"Automatically check for updates\":"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Text(
          "• Automation level Manual → posts Update Available (gated by `notifyOnUpdateAvailable`), since nothing downloads on its own."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Text(
          "• Automation level Auto-Download or Auto-Download-And-Install → the download hits this example's fake GitHub asset URL, which 404s, so it posts Update Failed (gated by `notifyOnUpdateFailure`)."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Text(
          "The first background check runs almost immediately after the toggle is switched on, not after the full interval."
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func simulateRelaunch(tag: String) {
    guard let executableURL = Bundle.main.executableURL else { return }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--sunshine-relaunched-from=\(tag)"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    exit(0)
  }
}

/// Empty state shown in place of `UpdateAvailableView` and `UpdateIndicatorView`.
/// It appears if there is no `pendingUpdate`, e.g. after "Skip This Version". Those views
/// expect a presenter to dismiss them when the state changes, as a sheet or a self-hiding
/// badge does. The example app shows them as standalone gallery screens, so it needs this
/// view to explain why no update is shown.
private struct NoPendingUpdateView: View {
  @ObservedObject var controller: SunshineUpdaterUIController

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.circle")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No update pending.")
        .foregroundStyle(.secondary)
      if let skipped = UserDefaults.standard.string(
        forKey: ExampleData.userDefaultsKeyPrefix + "skippedVersion")
      {
        Text("Version \(skipped) was skipped.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Button("Check for Updates") { controller.checkForUpdatesButtonTapped() }
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
