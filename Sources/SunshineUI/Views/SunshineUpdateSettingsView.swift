import SwiftUI
import SunshineCore

/// A drop-in "Updates" settings pane: app identity, then the standard auto-check /
/// auto-install / channel controls, in the style of apps like Tailscale's "About" tab.
/// Reads and writes `updater`'s live settings directly, so toggling here takes effect
/// immediately and persists across launches — no extra wiring needed.
public struct SunshineUpdateSettingsView: View {
    @ObservedObject var updater: SunshineUpdater
    let appName: String
    let appIcon: Image?
    let showChannelPicker: Bool

    @State private var isCheckingNow = false

    public init(
        updater: SunshineUpdater,
        appName: String = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "This app",
        appIcon: Image? = .fromMainBundle(),
        showChannelPicker: Bool = true
    ) {
        self.updater = updater
        self.appName = appName
        self.appIcon = appIcon
        self.showChannelPicker = showChannelPicker
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
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

                HStack(alignment: .center) {
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

                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Check Now") {
                            isCheckingNow = true
                            Task {
                                _ = await updater.checkForUpdates()
                                isCheckingNow = false
                            }
                        }
                        .disabled(isCheckingNow)

                        if let lastCheckDate = updater.lastCheckDate {
                            Text("Last check: \(lastCheckDate.formatted(date: .numeric, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

#if DEBUG
#Preview {
    SunshineUpdateSettingsView(updater: PreviewSupport.updater(), appName: "Example App")
}
#endif
