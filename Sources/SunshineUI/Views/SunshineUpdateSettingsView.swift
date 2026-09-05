import SwiftUI
import SunshineCore

/// A drop-in "Updates" settings pane: app identity, the standard auto-check /
/// auto-install / channel controls, a Check Now button, and — when a check finds
/// one — the update review (notes, Install & Relaunch, Skip, Remind Me Later)
/// inline, in the style of apps like Tailscale's "About" tab.
///
/// Reads and writes the updater's live settings directly, so toggling here takes
/// effect immediately and persists across launches. Check Now routes through
/// ``SunshineUpdaterUIController/refreshUpdateStatus()``, so a version the user
/// previously skipped or deferred is resurfaced here rather than reported as "up
/// to date". While this view is on screen it sets
/// ``SunshineUpdaterUIController/suppressesUpdateSheet``, so an update found here
/// shows in the pane rather than also popping as a sheet on another window.
public struct SunshineUpdateSettingsView: View {
    @ObservedObject var controller: SunshineUpdaterUIController
    // The toggles read and write settings on the updater, whose setters fire its
    // own `objectWillChange`; observe it directly or the checkboxes don't
    // repaint when toggled.
    @ObservedObject var updater: SunshineUpdater
    let appName: String
    let appIcon: Image?
    let showChannelPicker: Bool

    @State private var isCheckingNow = false
    @State private var showsUpToDate = false

    public init(
        controller: SunshineUpdaterUIController,
        appName: String = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "This app",
        appIcon: Image? = .fromMainBundle(),
        showChannelPicker: Bool = true
    ) {
        self.controller = controller
        self.updater = controller.updater
        self.appName = appName
        self.appIcon = appIcon
        self.showChannelPicker = showChannelPicker
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                if let appIcon {
                    appIcon.resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName).font(.title2.bold())
                    Text("Version \(AppVersion.fromMainBundle().shortVersion)")
                        .foregroundStyle(.secondary)
                }
            }

            // The review of a found update sits directly under the app identity,
            // above the settings controls.
            outcome

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Automatically Check For Updates", isOn: Binding(
                    get: { updater.isAutomaticallyCheckingForUpdates },
                    set: { updater.isAutomaticallyCheckingForUpdates = $0 }
                ))
                Toggle("Install Updates Automatically", isOn: Binding(
                    get: { updater.automationLevel == .autoDownloadAndInstall },
                    set: { updater.automationLevel = $0 ? .autoDownloadAndInstall : .manual }
                ))

                HStack(alignment: .firstTextBaseline) {
                    if showChannelPicker {
                        Picker("Update to:", selection: Binding(
                            get: { updater.allowPrereleases },
                            set: { updater.allowPrereleases = $0 }
                        )) {
                            Text("Stable versions").tag(false)
                            Text("Pre-release versions").tag(true)
                        }
                        .frame(maxWidth: 260)
                    }

                    Spacer()

                    Button("Check Now") { checkNow() }
                        .disabled(isCheckingNow)
                }

                if let lastCheckDate = updater.lastCheckDate {
                    Text("Last check: \(lastCheckDate.formatted(date: .numeric, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { controller.suppressesUpdateSheet = true }
        .onDisappear { controller.suppressesUpdateSheet = false }
    }

    @ViewBuilder
    private var outcome: some View {
        if controller.pendingUpdate != nil {
            card {
                UpdateReviewContent(
                    controller: controller, appName: appName, appIcon: appIcon,
                    showsAppIdentity: false, showsDismissActions: false)
            }
        } else if let message = controller.errorMessage {
            card {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if showsUpToDate {
            card {
                Label(
                    "\(appName) \(AppVersion.fromMainBundle().shortVersion) is the latest version.",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Sets the pending-update review off from the settings controls with a
    /// bordered, tinted container.
    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
    }

    private func checkNow() {
        isCheckingNow = true
        showsUpToDate = false
        Task {
            let result = await controller.refreshUpdateStatus()
            if case .noUpdateAvailable(nil, _) = result { showsUpToDate = true }
            isCheckingNow = false
        }
    }
}

#if DEBUG
#Preview {
    SunshineUpdateSettingsView(controller: PreviewSupport.controller(), appName: "Example App")
}
#endif
