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
  /// Set alongside `isPresentingUpToDateAlert` when the reason the check reported "up to
  /// date" is that the newest release was previously skipped or deferred with "Remind Me Later". It
  /// lets the up-to-date alert offer a way back to that update.
  @Published public private(set) var skippedUpdate: Update?
  @Published public private(set) var pendingUpdate: Update?
  @Published public private(set) var progress: Double = 0
  @Published public private(set) var errorMessage: String?
  /// True from the moment the user taps "Install & Relaunch" until the process finishes,
  /// fails, or the app exits to relaunch. Drives the sheet's progress UI.
  @Published public private(set) var isInstalling: Bool = false
  /// Human-readable description of the current install phase, e.g. "Verifying update…".
  @Published public private(set) var statusText: String = ""
  /// True only while the download is in flight. Drives the Cancel button, which is
  /// hidden once verification starts, since nothing after that point is cancellable.
  @Published public private(set) var isDownloading: Bool = false

  /// Set by `.sunshineUpdater(_:style:)` to control whether a newly discovered update
  /// auto-presents `isPresentingUpdateSheet`, or just becomes available for a passive
  /// indicator (e.g. `UpdateIndicatorView`) to surface on its own.
  public var updateUIStyle: SunshineUpdateUIStyle = .sheet

  /// While true, a newly discovered update or error populates `pendingUpdate` /
  /// `errorMessage` but does not raise `isPresentingUpdateSheet`. A host showing
  /// the review itself (e.g. `SunshineUpdateSettingsView`) sets this while it is
  /// on screen so the same update does not also pop as a sheet on another window.
  @Published public var suppressesUpdateSheet = false

  private var cancellable: AnyCancellable?
  /// True while the task started by `installTapped()` runs, to tell a user-initiated
  /// install apart from a background download under `.autoDownload`.
  private var isInstallTaskRunning = false

  public init(updater: SunshineUpdater) {
    self.updater = updater
    // Terminate through AppKit rather than `exit(0)` so the app delegate, autosave,
    // and any unsaved-changes prompt run before the bundle is swapped.
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
      // Also the state a cancelled download returns to, so the review has to come
      // back out of its progress presentation.
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

  /// Runs a user-initiated check and leaves the outcome in the controller's
  /// published state, presenting nothing itself. A previously skipped or deferred
  /// version is resurfaced as `pendingUpdate` (the engine otherwise reports it as
  /// "up to date"), so a host that renders the review inline, such as the settings pane,
  /// can show it. Returns the raw result for any further host handling.
  ///
  /// Use this when the review is shown in your own UI. Use
  /// ``checkForUpdatesButtonTapped()`` when you want the ready-made sheet/alert.
  @discardableResult
  public func refreshUpdateStatus() async -> UpdateCheckResult {
    let result = await updater.checkForUpdates()
    switch result {
    case .noUpdateAvailable(let latestKnown?, _):
      // The engine treats a skipped/deferred version as up to date. A manual
      // check is an explicit "show me updates", so drop those filters and
      // surface it as pending.
      updater.clearSkippedVersion()
      pendingUpdate = latestKnown
      errorMessage = nil
    case .noUpdateAvailable(nil, _):
      pendingUpdate = nil
      errorMessage = nil
    case .updateAvailable, .failed:
      break  // The state sink populates pendingUpdate / errorMessage.
    }
    return result
  }

  /// Reinstates a version the user previously skipped (or is reminding-later on) and
  /// presents it as a pending update, offered as an action on the "up to date" alert.
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
        // Reuse an update already downloaded and verified, e.g. by the background
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
        // The user asked for this, so the review comes back with no error shown.
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

  /// Cancels an in-flight download and returns the UI to the update review. Has no
  /// effect once verification has started.
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
