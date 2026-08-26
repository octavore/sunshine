import SwiftUI
import SunshineCore
import SunshineUI

enum ExampleScreen: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case updateAvailable = "Update Available"
    case updateIndicator = "Update Indicator"
    case updateError = "Update Error"
    case downloadProgress = "Download Progress"

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var screen: ExampleScreen = .settings
    @StateObject private var updater: SunshineUpdater
    @StateObject private var controller: SunshineUpdaterUIController

    init() {
        let updater = ExampleData.updater()
        _updater = StateObject(wrappedValue: updater)
        _controller = StateObject(wrappedValue: SunshineUpdaterUIController(updater: updater))
    }

    var body: some View {
        NavigationSplitView {
            List(ExampleScreen.allCases, selection: $screen) { screen in
                Text(screen.rawValue).tag(screen)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            screenView
                .task { _ = await controller.updater.checkForUpdates() }
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    @ViewBuilder
    private var screenView: some View {
        switch screen {
        case .settings:
            SunshineUpdateSettingsView(updater: updater, appName: "Example App")
        case .updateAvailable:
            UpdateAvailableView(controller: controller, appName: "Example App")
        case .updateIndicator:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
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
        }
    }
}
