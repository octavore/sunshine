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
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if style == .cornerIndicator {
                    UpdateIndicatorView(controller: controller, appName: appName, appIcon: appIcon)
                        .padding(16)
                }
            }
            .alert("You're up to date!", isPresented: $controller.isPresentingUpToDateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(appName) \(AppVersion.fromMainBundle().shortVersion) is the latest version.")
            }
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
