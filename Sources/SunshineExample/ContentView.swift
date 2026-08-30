import SwiftUI
import SunshineCore
import SunshineUI

enum ExampleScreen: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case updateAvailable = "Update Available"
    case updateIndicator = "Update Indicator"
    case updateError = "Update Error"
    case downloadProgress = "Download Progress"
    case configuration = "Configuration"

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

/// Owns the `SunshineUpdater`/`SunshineUpdaterUIController` pair, rebuilt from scratch
/// whenever the enclosing `ContentView` gives it a new identity (see `.id(releaseConfig)`)
/// so changes made on the `Configuration` screen take effect.
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
            SunshineUpdateSettingsView(updater: updater, appName: "Example App")
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
                UpdateIndicatorView(controller: controller, appName: "Example App")
                    .padding(16)
            }
        case .updateError:
            UpdateErrorView(
                message: "The GitHub API rate limit was exceeded. Try again after 5:00 PM.",
                releaseURL: URL(string: "https://github.com/example/example/releases/latest")
            )
        case .downloadProgress:
            DownloadProgressView(fractionComplete: 0.62, onCancel: {})
        case .configuration:
            ExampleConfigurationView(controller: controller, appliedReleaseConfig: releaseConfig) { releaseConfig = $0 }
        }
    }
}

/// Shown in place of `UpdateAvailableView`/`UpdateIndicatorView` once there's no
/// `pendingUpdate` to display (e.g. right after "Skip This Version"). Those views assume a
/// presenter dismisses them once state changes (they're normally shown in a sheet or a
/// self-hiding badge); the example app displays them as standalone gallery screens, so it
/// needs its own empty state to explain why nothing update-related is showing.
private struct NoPendingUpdateView: View {
    @ObservedObject var controller: SunshineUpdaterUIController

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No update pending.")
                .foregroundStyle(.secondary)
            if let skipped = UserDefaults.standard.string(forKey: ExampleData.userDefaultsKeyPrefix + "skippedVersion") {
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
