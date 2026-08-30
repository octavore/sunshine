import SwiftUI
import SunshineCore

private struct SunshineUpdaterModifier: ViewModifier {
    @ObservedObject var controller: SunshineUpdaterUIController
    let appName: String
    let appIcon: Image?
    let style: SunshineUpdateUIStyle

    func body(content: Content) -> some View {
        content
            .task {
                controller.updateUIStyle = style
                await controller.startIfConfigured()
            }
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
                    Text("The latest version of \(appName) is \(skippedUpdate.version.shortVersion). You have \(AppVersion.fromMainBundle().shortVersion).")
                } else {
                    Text(upToDateMessage(appName: appName, releaseURL: controller.upToDateReleaseURL))
                }
            }
    }

    /// "\(appName) \(version) is the latest version.", with the name and version linking out
    /// to the GitHub release page when one is known. Building this as an `AttributedString`
    /// (rather than interpolating into a Markdown string) avoids `appName` breaking parsing
    /// if it contains Markdown-special characters.
    private func upToDateMessage(appName: String, releaseURL: URL?) -> AttributedString {
        var linkRun = AttributedString("\(appName) \(AppVersion.fromMainBundle().shortVersion)")
        if let releaseURL {
            linkRun.link = releaseURL
        }
        return linkRun + AttributedString(" is the latest version.")
    }
}

extension View {
    /// Attaches Sunshine's ready-made update UI and starts its background check loop
    /// (if `checkInterval` is configured). This is the minimal-setup integration path —
    /// attach it once, near the root of your scene.
    ///
    /// - Parameter style: `.sheet` (default) interrupts with a modal as soon as an update
    ///   is found. `.cornerIndicator` instead shows a small badge in the bottom-trailing
    ///   corner that the user opens when ready — see
    ///   https://mitchellh.com/writing/non-trivial-vibing for the design this mirrors.
    public func sunshineUpdater(
        _ controller: SunshineUpdaterUIController,
        appName: String = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "This app",
        appIcon: Image? = .fromMainBundle(),
        style: SunshineUpdateUIStyle = .sheet
    ) -> some View {
        modifier(SunshineUpdaterModifier(controller: controller, appName: appName, appIcon: appIcon, style: style))
    }
}
