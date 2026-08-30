import Foundation
import Combine
import SunshineCore

@MainActor
public final class SunshineUpdaterUIController: ObservableObject {
    public let updater: SunshineUpdater

    @Published public var isPresentingUpdateSheet: Bool = false
    @Published public var isPresentingUpToDateAlert: Bool = false
    @Published public private(set) var upToDateReleaseURL: URL?
    /// Set alongside `isPresentingUpToDateAlert` when the reason the check reported "up to
    /// date" is that the newest release was previously skipped or is being reminded-later —
    /// lets the up-to-date alert offer a way back to that update instead of dead-ending.
    @Published public private(set) var skippedUpdate: Update?
    @Published public private(set) var pendingUpdate: Update?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var errorMessage: String?
    /// True from the moment the user taps "Install & Relaunch" until the process finishes,
    /// fails, or the app exits to relaunch. Drives the sheet's progress UI.
    @Published public private(set) var isInstalling: Bool = false
    /// Human-readable description of the current install phase, e.g. "Verifying update…".
    @Published public private(set) var statusText: String = ""

    /// Set by `.sunshineUpdater(_:style:)` to control whether a newly discovered update
    /// auto-presents `isPresentingUpdateSheet`, or just becomes available for a passive
    /// indicator (e.g. `UpdateIndicatorView`) to surface on its own.
    public var updateUIStyle: SunshineUpdateUIStyle = .sheet

    private var cancellable: AnyCancellable?
    private var didStart = false

    public init(updater: SunshineUpdater) {
        self.updater = updater
        cancellable = updater.$state.sink { [weak self] state in
            self?.handle(state)
        }
    }

    private func handle(_ state: UpdateState) {
        switch state {
        case .updateAvailable(let update):
            pendingUpdate = update
            errorMessage = nil
            if updateUIStyle == .sheet {
                isPresentingUpdateSheet = true
            }
        case .downloading(_, let fraction):
            progress = fraction
            isInstalling = true
            statusText = "Downloading update…"
        case .verifying:
            isInstalling = true
            progress = 0
            statusText = "Verifying update…"
        case .readyToInstall(let update):
            pendingUpdate = update
            statusText = "Preparing to install…"
        case .installing:
            isInstalling = true
            progress = 0
            statusText = "Installing and relaunching…"
        case .error(let error):
            isInstalling = false
            errorMessage = "\(error)"
            if updateUIStyle == .sheet {
                isPresentingUpdateSheet = true
            }
        case .upToDate:
            isPresentingUpdateSheet = false
            isInstalling = false
            pendingUpdate = nil
            errorMessage = nil
        default:
            break
        }
    }

    /// Kicks off the automatic background-check loop if `checkInterval` is configured.
    /// Safe to call multiple times; only starts once. Called by `.sunshineUpdater(_:)`.
    public func startIfConfigured() async {
        guard !didStart else { return }
        didStart = true
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
        statusText = "Starting update…"
        Task {
            do {
                let downloaded = try await updater.download(pendingUpdate)
                let verified = try await updater.verify(downloaded)
                try await updater.install(verified)
            } catch {
                isInstalling = false
                errorMessage = "\(error)"
            }
        }
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
