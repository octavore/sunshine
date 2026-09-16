import SunshineCore
import SwiftUI

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
    UpdateReviewContent(controller: controller, appName: appName, appIcon: appIcon)
      .padding(20)
      .frame(width: 420)
  }
}

/// The update-review UI (version delta, release notes, and the install / skip /
/// remind actions, or install progress) without any outer padding or fixed
/// width, so it fits both `UpdateAvailableView`'s sheet and an inline spot in a
/// settings pane.
struct UpdateReviewContent: View {
  @ObservedObject var controller: SunshineUpdaterUIController
  let appName: String
  let appIcon: Image?
  /// Whether to draw the app icon and name. Off when the host already shows
  /// app identity above this view (the settings pane), so it isn't repeated.
  var showsAppIdentity: Bool = true
  /// Whether to offer "Skip This Version" and "Remind Me Later" alongside
  /// "Install & Relaunch". Off in the settings pane, where the user navigated
  /// here to act and a skip is undone by the next Check Now anyway.
  var showsDismissActions: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        if showsAppIdentity, let appIcon {
          appIcon.resizable().frame(width: 48, height: 48)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(
            showsAppIdentity
              ? "A new version of \(appName) is available!" : "A new version is available"
          )
          .font(.headline)
          if let update = controller.pendingUpdate {
            Text("\(AppVersion.fromMainBundle().shortVersion) → \(update.version.shortVersion)")
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }

      if let releaseNotes = ReleaseNotesRenderer.render(
        controller.pendingUpdate?.releaseNotesMarkdown)
      {
        ScrollView {
          Text(releaseNotes)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(minHeight: 120, maxHeight: 240)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }

      if controller.isInstalling {
        VStack(alignment: .leading, spacing: 6) {
          if controller.progress > 0 && controller.progress < 1 {
            ProgressView(value: controller.progress) {
              Text(controller.statusText)
            }
          } else {
            ProgressView {
              Text(controller.statusText)
            }
            .progressViewStyle(.linear)
          }
          // Only the download is cancellable; the button goes away once
          // verification starts rather than sitting there doing nothing.
          if controller.isDownloading {
            HStack {
              Spacer()
              Button("Cancel") { controller.cancelDownloadTapped() }
            }
          }
        }
        .frame(maxWidth: .infinity)
      } else {
        HStack {
          if showsDismissActions {
            Button("Skip This Version") { controller.skipTapped() }
            Spacer()
            Button("Remind Me Later") { controller.remindLaterTapped() }
          } else {
            Spacer()
          }
          Button("Install & Relaunch") { controller.installTapped() }
            .keyboardShortcut(.defaultAction)
        }
      }
    }
  }
}

#if DEBUG
  #Preview {
    UpdateAvailableView(controller: PreviewSupport.controller(), appName: "Example App")
  }
#endif
