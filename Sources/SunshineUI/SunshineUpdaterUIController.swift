import AppKit
import Combine
import Foundation
import SunshineCore

@MainActor
public final class SunshineUpdaterUIController: ObservableObject {
  public let updater: SunshineUpdater

  @Published public var isPresentingUpdateSheet: Bool = false
  @Published public var isPresentingUpToDateAlert: Bool = false
  @Published public private(set) var upToDateReleaseURL: URL?
  /// Skipped or deferred update, set with `isPresentingUpToDateAlert`.
  /// It is set if the check reported "up to date" because the newest release was skipped or
  /// deferred with "Remind Me Later". The up-to-date alert then offers a way back to that
  /// update.
  @Published public private(set) var skippedUpdate: Update?
  @Published public private(set) var pendingUpdate: Update?
  @Published public private(set) var progress: Double = 0
  @Published public private(set) var errorMessage: String?
  /// Whether an install is in progress.
  /// It is true from the "Install & Relaunch" tap until the process finishes, fails, or the
  /// app exits to relaunch. The sheet shows its progress UI while it is true.
  @Published public private(set) var isInstalling: Bool = false
  /// Description of the current install phase, e.g. "Verifying update…".
  @Published public private(set) var statusText: String = ""
  /// Whether a download is in flight.
  /// The Cancel button is shown while it is true. The button is hidden once verification
  /// starts, because later phases are not cancellable.
  @Published public private(set) var isDownloading: Bool = false

  /// Presentation of a newly discovered update.
  /// `.sunshineUpdater(_:style:)` sets it. `.sheet` presents `isPresentingUpdateSheet`
  /// automatically. Otherwise the update is only available to a passive indicator such as
  /// `UpdateIndicatorView`.
  public var updateUIStyle: SunshineUpdateUIStyle = .sheet

  /// Suppression of the update sheet.
  /// While true, a newly discovered update or error populates `pendingUpdate` and
  /// `errorMessage` and does not set `isPresentingUpdateSheet`. A host that shows the
  /// review itself, e.g. `SunshineUpdateSettingsView`, sets this while it is on screen.
  /// The same update then does not also open as a sheet on another window.
  @Published public var suppressesUpdateSheet = false

  private var cancellable: AnyCancellable?
  /// Whether the task started by `installTapped()` is running.
  /// It separates a user-initiated install from a background download under `.autoDownload`.
  private var isInstallTaskRunning = false

  public init(updater: SunshineUpdater) {
    self.updater = updater
    // Terminate through AppKit and not `exit(0)`. The app delegate, autosave, and any
    // unsaved-changes prompt then run before the bundle is swapped.
    updater.terminate = { NSApp.terminate(nil) }
    cancellable = updater.$state.sink { [weak self] state in
      self?.handle(state)
    }
  }

  private func handle(_ state: UpdateState) {
    switch state {
    case .updateAvailable(let update):
      pendingUpdate = update
      errorMessage = nil
      // A cancelled download also returns to this state. The review must leave its
      // progress presentation.
      isInstalling = false
      isDownloading = false
      progress = 0
      if updateUIStyle == .sheet && !suppressesUpdateSheet {
        isPresentingUpdateSheet = true
      }
    case .downloading(_, let fraction):
      progress = fraction
      isInstalling = true
      isDownloading = true
      statusText = "Downloading update…"
    case .verifying:
      isInstalling = true
      isDownloading = false
      progress = 0
      statusText = "Verifying update…"
    case .readyToInstall(let update):
      pendingUpdate = update
      if isInstallTaskRunning {
        statusText = "Preparing to install…"
      } else {
        // Downloaded and verified in the background. The review returns with
        // Install & Relaunch, which installs the verified update.
        isInstalling = false
        isDownloading = false
        progress = 0
        if updateUIStyle == .sheet && !suppressesUpdateSheet {
          isPresentingUpdateSheet = true
        }
      }
    case .installing:
      isInstalling = true
      progress = 0
      statusText = "Installing and relaunching…"
    case .error(let error):
      isInstalling = false
      isDownloading = false
      errorMessage = "\(error)"
      if updateUIStyle == .sheet && !suppressesUpdateSheet {
        isPresentingUpdateSheet = true
      }
    case .upToDate:
      isPresentingUpdateSheet = false
      isInstalling = false
      isDownloading = false
      pendingUpdate = nil
      errorMessage = nil
    default:
      break
    }
  }

  private static let suppressMoveAlertKey = "SunshineSuppressMoveToApplicationsAlert"

  /// Ask whether to move the app to the Applications folder.
  /// The alert appears if the app runs from a location where it cannot update itself. Call
  /// this once at launch. It does nothing in a suitable location, or after the user chose
  /// not to be asked again. On "Move", the app is copied, relaunched from the copy, and
  /// terminated.
  public func offerToMoveToApplicationsIfNeeded() {
    guard updater.shouldOfferMoveToApplications,
      !UserDefaults.standard.bool(forKey: Self.suppressMoveAlertKey)
    else { return }

    let alert = NSAlert()
    alert.messageText = "Move to Applications folder?"
    alert.informativeText =
      "This app is running from a location where it cannot update itself. It can move itself to the Applications folder and relaunch."
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Don't Move")
    alert.showsSuppressionButton = true

    let response = alert.runModal()
    if alert.suppressionButton?.state == .on {
      UserDefaults.standard.set(true, forKey: Self.suppressMoveAlertKey)
    }
    guard response == .alertFirstButtonReturn else { return }

    do {
      try updater.moveToApplicationsAndRelaunch()
    } catch {
      let failure = NSAlert()
      failure.messageText = "Could not move the app"
      failure.informativeText = "\(error)"
      failure.runModal()
    }
  }

  public func checkForUpdatesButtonTapped() {
    Task {
      let result = await updater.checkForUpdates()
      if case .noUpdateAvailable(let latestKnown, let releaseURL) = result {
        upToDateReleaseURL = latestKnown?.htmlURL ?? releaseURL
        skippedUpdate = latestKnown
        isPresentingUpToDateAlert = true
      }
    }
  }

  /// Run a user-initiated check and store the outcome in the published state.
  /// This presents nothing. A skipped or deferred version is shown again as
  /// `pendingUpdate`, where the engine would report "up to date". A host that renders the
  /// review inline, such as the settings pane, can then show it. Returns the raw result
  /// for further host handling.
  ///
  /// Use this if the review is shown in your own UI. Use
  /// ``checkForUpdatesButtonTapped()`` for the ready-made sheet and alert.
  @discardableResult
  public func refreshUpdateStatus() async -> UpdateCheckResult {
    let result = await updater.checkForUpdates()
    switch result {
    case .noUpdateAvailable(let latestKnown?, _):
      // The engine treats a skipped or deferred version as up to date. A manual check
      // asks to see updates. Clear those filters and show the version as pending.
      updater.clearSkippedVersion()
      pendingUpdate = latestKnown
      errorMessage = nil
    case .noUpdateAvailable(nil, _):
      pendingUpdate = nil
      errorMessage = nil
    case .updateAvailable, .failed:
      break  // The state sink populates pendingUpdate and errorMessage.
    }
    return result
  }

  /// Reinstate a version the user skipped or deferred and present it as a pending update.
  /// The "up to date" alert offers this as an action.
  public func viewSkippedUpdateTapped() {
    guard let skippedUpdate else { return }
    updater.clearSkippedVersion()
    isPresentingUpToDateAlert = false
    pendingUpdate = skippedUpdate
    self.skippedUpdate = nil
    isPresentingUpdateSheet = true
  }

  public func installTapped() {
    guard let pendingUpdate else { return }
    isInstalling = true
    isInstallTaskRunning = true
    statusText = "Starting update…"
    Task {
      defer { isInstallTaskRunning = false }
      do {
        // Reuse an update that is already downloaded and verified, e.g. by the background
        // loop under `.autoDownload`. `install(_:)` verifies it again before the swap.
        let verified: VerifiedUpdate
        if let ready = updater.verifiedUpdate, ready.update == pendingUpdate {
          verified = ready
        } else {
          let downloaded = try await updater.download(pendingUpdate)
          verified = try await updater.verify(downloaded)
        }
        try await updater.install(verified)
      } catch SunshineError.cancelled {
        // The user requested the cancel. The review returns without an error.
        isInstalling = false
        isDownloading = false
        errorMessage = nil
      } catch {
        isInstalling = false
        isDownloading = false
        errorMessage = "\(error)"
      }
    }
  }

  /// Cancel an in-flight download and return the UI to the update review.
  /// This has no effect once verification starts.
  public func cancelDownloadTapped() {
    updater.cancelDownload()
  }

  public func remindLaterTapped() {
    guard let pendingUpdate else { return }
    updater.remindLater(pendingUpdate)
    isPresentingUpdateSheet = false
    self.pendingUpdate = nil
  }

  public func skipTapped() {
    guard let pendingUpdate else { return }
    updater.skip(pendingUpdate)
    isPresentingUpdateSheet = false
    self.pendingUpdate = nil
  }
}
