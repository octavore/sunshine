import SwiftUI
import SunshineCore

/// A small, non-blocking badge for `SunshineUpdateUIStyle.cornerIndicator`. Sits in the
/// window's bottom-trailing corner and opens the full update review in a popover on tap,
/// instead of interrupting the user with a sheet the moment an update is found.
public struct UpdateIndicatorView: View {
    @ObservedObject var controller: SunshineUpdaterUIController
    let appName: String
    let appIcon: Image?

    @State private var isPresentingPopover = false

    public init(controller: SunshineUpdaterUIController, appName: String, appIcon: Image? = nil) {
        self.controller = controller
        self.appName = appName
        self.appIcon = appIcon
    }

    public var body: some View {
        if controller.pendingUpdate != nil || controller.errorMessage != nil {
            Button {
                isPresentingPopover = true
            } label: {
                HStack(spacing: 6) {
                    if let appIcon {
                        appIcon.resizable().frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: controller.errorMessage != nil ? "exclamationmark.circle.fill" : "arrow.down.circle.fill")
                    }
                    Text(controller.errorMessage != nil ? "Update Failed" : "Update Available")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresentingPopover, arrowEdge: .bottom) {
                if let message = controller.errorMessage {
                    UpdateErrorView(message: message, releaseURL: controller.pendingUpdate?.htmlURL)
                } else {
                    UpdateAvailableView(controller: controller, appName: appName, appIcon: appIcon)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: controller.pendingUpdate != nil)
        }
    }
}
