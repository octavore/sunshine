import SwiftUI
import SunshineCore

public struct UpdateAvailableView: View {
    @ObservedObject var controller: SunshineUpdaterUIController
    let appName: String
    let appIcon: Image?

    public init(controller: SunshineUpdaterUIController, appName: String, appIcon: Image? = nil) {
        self.controller = controller
        self.appName = appName
        self.appIcon = appIcon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let appIcon {
                    appIcon.resizable().frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("A new version of \(appName) is available!")
                        .font(.headline)
                    if let update = controller.pendingUpdate {
                        Text("\(AppVersion.fromMainBundle().shortVersion) → \(update.version.shortVersion)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ScrollView {
                Text(ReleaseNotesRenderer.render(controller.pendingUpdate?.releaseNotesMarkdown))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if controller.progress > 0 && controller.progress < 1 {
                ProgressView(value: controller.progress)
            }

            HStack {
                Button("Skip This Version") { controller.skipTapped() }
                Spacer()
                Button("Remind Me Later") { controller.remindLaterTapped() }
                Button("Install & Relaunch") { controller.installTapped() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
