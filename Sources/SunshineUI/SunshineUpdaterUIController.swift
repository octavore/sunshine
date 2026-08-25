import Foundation
import Combine
import SunshineCore

@MainActor
public final class SunshineUpdaterUIController: ObservableObject {
    public let updater: SunshineUpdater

    @Published public var isPresentingUpdateSheet: Bool = false
    @Published public private(set) var pendingUpdate: Update?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var errorMessage: String?

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
            isPresentingUpdateSheet = true
        case .downloading(_, let fraction):
            progress = fraction
        case .readyToInstall(let update):
            pendingUpdate = update
        case .error(let error):
            errorMessage = "\(error)"
            isPresentingUpdateSheet = true
        case .upToDate:
            isPresentingUpdateSheet = false
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
            if case .noUpdateAvailable = result {
                isPresentingUpdateSheet = true
            }
        }
    }

    public func installTapped() {
        guard let pendingUpdate else { return }
        Task {
            do {
                let downloaded = try await updater.download(pendingUpdate)
                let verified = try await updater.verify(downloaded)
                try await updater.install(verified)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    public func remindLaterTapped() {
        guard let pendingUpdate else { return }
        updater.remindLater(pendingUpdate)
        isPresentingUpdateSheet = false
    }

    public func skipTapped() {
        guard let pendingUpdate else { return }
        updater.skip(pendingUpdate)
        isPresentingUpdateSheet = false
    }
}
