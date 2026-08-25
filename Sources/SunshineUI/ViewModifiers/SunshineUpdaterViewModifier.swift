import SwiftUI
import SunshineCore

private struct SunshineUpdaterModifier: ViewModifier {
    @ObservedObject var controller: SunshineUpdaterUIController
    let appName: String
    let appIcon: Image?

    func body(content: Content) -> some View {
        content
            .task { await controller.startIfConfigured() }
            .sheet(isPresented: $controller.isPresentingUpdateSheet) {
                if let message = controller.errorMessage {
                    UpdateErrorView(message: message, releaseURL: controller.pendingUpdate?.htmlURL)
                } else {
                    UpdateAvailableView(controller: controller, appName: appName, appIcon: appIcon)
                }
            }
    }
}

extension View {
    /// Attaches Sunshine's ready-made update UI and starts its background check loop
    /// (if `checkInterval` is configured). This is the minimal-setup integration path —
    /// attach it once, near the root of your scene.
    public func sunshineUpdater(
        _ controller: SunshineUpdaterUIController,
        appName: String = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "This app",
        appIcon: Image? = nil
    ) -> some View {
        modifier(SunshineUpdaterModifier(controller: controller, appName: appName, appIcon: appIcon))
    }
}
