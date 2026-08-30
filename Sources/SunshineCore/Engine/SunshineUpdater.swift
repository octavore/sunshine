import Foundation
import Combine

/// The core update engine: checks GitHub Releases, downloads, verifies against the
/// running app's code signature, and swaps the new bundle into place. Usable headlessly
/// (no UI import) or driven by `SunshineUI`'s `SunshineUpdaterUIController`.
@MainActor
public final class SunshineUpdater: ObservableObject {
    @Published public private(set) var state: UpdateState = .idle

    public weak var delegate: (any SunshineUpdaterDelegate)?

    private var configuration: SunshineConfiguration
    private let client: any ReleasesProviding
    private let verifier: UpdateVerifier
    private let store: SkipAndRemindStore
    private let preferencesStore: UpdatePreferencesStore
    private let bundleIdentifier: String
    private let installURL: URL

    private var eventContinuation: AsyncStream<UpdateEvent>.Continuation?
    public lazy var events: AsyncStream<UpdateEvent> = AsyncStream { continuation in
        self.eventContinuation = continuation
    }

    private var schedulingTask: Task<Void, Never>?
    private var currentVerified: VerifiedUpdate?

    /// - Parameter releasesProvider: Source of release data. Defaults to a real
    ///   `GitHubReleasesClient`; pass a `StaticReleasesProvider` to drive this updater from a
    ///   fixed list of releases instead, e.g. for SwiftUI previews, examples, or tests.
    public init(configuration: SunshineConfiguration, releasesProvider: (any ReleasesProviding)? = nil) {
        self.configuration = configuration
        self.client = releasesProvider ?? GitHubReleasesClient(token: configuration.githubToken)
        self.verifier = UpdateVerifier(requireNotarization: configuration.requireNotarization)
        let bundleID = Bundle.main.bundleIdentifier ?? "\(configuration.owner).\(configuration.repo)"
        self.bundleIdentifier = bundleID
        self.installURL = configuration.installLocation ?? Bundle.main.bundleURL
        self.store = SkipAndRemindStore(bundleIdentifier: bundleID)
        self.preferencesStore = UpdatePreferencesStore(bundleIdentifier: bundleID)

        if let savedAutoCheck = preferencesStore.automaticallyCheckForUpdates {
            self.configuration.checkInterval = savedAutoCheck ? (configuration.checkInterval ?? 3600) : nil
        }
        if let savedLevel = preferencesStore.automationLevel {
            self.configuration.automationLevel = savedLevel
        }
        if let savedPrereleases = preferencesStore.allowPrereleases {
            self.configuration.allowPrereleases = savedPrereleases
        }

        // Confirm a pending relaunch handshake automatically, so the host app does not
        // have to wire `confirmSuccessfulRelaunchIfNeeded()` itself. This is a no-op
        // unless the process was started by RelaunchCoordinator.
        RelaunchCoordinator.confirmSuccessfulRelaunchIfNeeded(bundleIdentifier: bundleID)

        InstallSession.sweepStaleAsideBundles(near: installURL)

        if self.configuration.checkInterval != nil {
            startAutomaticChecking()
        }
    }

    // MARK: - Live settings (for `SunshineUpdateSettingsView`)

    /// Whether the background check loop is running. Setting this persists the preference
    /// and starts/stops the loop immediately.
    public var isAutomaticallyCheckingForUpdates: Bool {
        get { configuration.checkInterval != nil }
        set {
            objectWillChange.send()
            preferencesStore.automaticallyCheckForUpdates = newValue
            if newValue {
                configuration.checkInterval = configuration.checkInterval ?? 3600
                startAutomaticChecking()
            } else {
                configuration.checkInterval = nil
                schedulingTask?.cancel()
                schedulingTask = nil
            }
        }
    }

    /// Whether a found update should download, verify, and install unattended. Persists
    /// the preference immediately.
    public var automationLevel: UpdateAutomationLevel {
        get { configuration.automationLevel }
        set {
            objectWillChange.send()
            configuration.automationLevel = newValue
            preferencesStore.automationLevel = newValue
        }
    }

    /// Whether prerelease GitHub releases are eligible updates. Persists the preference
    /// immediately.
    public var allowPrereleases: Bool {
        get { configuration.allowPrereleases }
        set {
            objectWillChange.send()
            configuration.allowPrereleases = newValue
            preferencesStore.allowPrereleases = newValue
        }
    }

    /// When the most recent check (successful or not) ran, for display in settings UI.
    public var lastCheckDate: Date? { store.lastCheckDate() }

    // MARK: - Headless / programmatic API

    public func checkForUpdates() async -> UpdateCheckResult {
        emit(.checkStarted)
        state = .checking

        guard !isSandboxed() else {
            let result = UpdateCheckResult.failed(.sandboxedAppUnsupported)
            state = .error(.sandboxedAppUnsupported)
            emit(.checkFinished(result))
            return result
        }

        do {
            let releases: [GitHubRelease]
            if configuration.allowPrereleases {
                releases = try await client.fetchRecentReleases(owner: configuration.owner, repo: configuration.repo)
                    .filter { !$0.draft }
                    .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            } else {
                releases = [try await client.fetchLatestRelease(owner: configuration.owner, repo: configuration.repo)]
            }

            store.recordCheckAttempt(succeeded: true, baseInterval: configuration.checkInterval ?? 3600)

            guard let latest = releases.first else {
                state = .upToDate
                let result = UpdateCheckResult.noUpdateAvailable(latestKnown: nil)
                emit(.checkFinished(result))
                return result
            }

            let runningVersion = AppVersion.fromMainBundle()
            let candidateVersion = AppVersion(tag: latest.tagName)

            guard runningVersion.isUpdate(candidateVersion) else {
                state = .upToDate
                let result = UpdateCheckResult.noUpdateAvailable(latestKnown: nil, releaseURL: latest.htmlURL)
                emit(.checkFinished(result))
                return result
            }

            let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String
            guard let asset = AssetMatcher.select(from: latest.assets, matching: configuration.assetMatcher, bundleName: bundleName) else {
                let result = UpdateCheckResult.failed(.noMatchingAsset)
                state = .error(.noMatchingAsset)
                emit(.checkFinished(result))
                return result
            }

            var update = Update(release: latest, asset: asset)
            update = aggregatingReleaseNotes(for: update, allReleases: releases, runningVersion: runningVersion)

            if store.skippedVersion() == update.id || store.isRemindingLater() {
                state = .upToDate
                let result = UpdateCheckResult.noUpdateAvailable(latestKnown: update, releaseURL: update.htmlURL)
                emit(.checkFinished(result))
                return result
            }

            state = .updateAvailable(update)
            let result = UpdateCheckResult.updateAvailable(update)
            delegate?.updater(self, didFindUpdate: update)
            emit(.checkFinished(result))
            return result
        } catch let error as SunshineError {
            store.recordCheckAttempt(succeeded: false, baseInterval: configuration.checkInterval ?? 3600)
            state = .error(error)
            delegate?.updater(self, didFailWithError: error)
            let result = UpdateCheckResult.failed(error)
            emit(.checkFinished(result))
            return result
        } catch {
            store.recordCheckAttempt(succeeded: false, baseInterval: configuration.checkInterval ?? 3600)
            let wrapped = SunshineError.network(underlying: error)
            state = .error(wrapped)
            delegate?.updater(self, didFailWithError: wrapped)
            let result = UpdateCheckResult.failed(wrapped)
            emit(.checkFinished(result))
            return result
        }
    }

    /// Combines the release notes of every release newer than `runningVersion` (not just
    /// the latest), newest first, so a user who skipped several versions sees them all.
    private func aggregatingReleaseNotes(for update: Update, allReleases: [GitHubRelease], runningVersion: AppVersion) -> Update {
        let skipped = allReleases.filter { runningVersion.isUpdate(AppVersion(tag: $0.tagName)) }
        guard skipped.count > 1 else { return update }
        let combined = skipped.compactMap { release -> String? in
            guard let body = release.body, !body.isEmpty else { return nil }
            return "## \(release.tagName)\n\n\(body)"
        }.joined(separator: "\n\n---\n\n")
        return Update(release: GitHubRelease(
            tagName: update.id, name: nil, body: combined, draft: false,
            prerelease: update.isPrerelease, publishedAt: update.publishedAt,
            htmlURL: update.htmlURL, assets: [update.asset]
        ), asset: update.asset)
    }

    public func download(_ update: Update) async throws -> DownloadedUpdate {
        state = .downloading(update, fractionComplete: 0)
        let tempDirectory = SunshineCache.updateDirectory(forBundleIdentifier: bundleIdentifier, releaseTag: update.id)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let archiveURL = tempDirectory.appendingPathComponent(update.asset.name)

        do {
            let progressDelegate = DownloadProgressForwarder { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
                    self.state = .downloading(update, fractionComplete: fraction)
                    self.emit(.downloadProgress(
                        fractionComplete: fraction,
                        bytesWritten: Int64(Double(update.asset.size) * fraction),
                        bytesTotal: Int64(update.asset.size)))
                }
            }
            let request = URLRequest(url: update.asset.browserDownloadURL)
            let (downloadedURL, _) = try await URLSession.shared.download(for: request, delegate: progressDelegate)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
        } catch {
            let wrapped = SunshineError.downloadFailed(underlying: error)
            state = .error(wrapped)
            throw wrapped
        }

        state = .downloading(update, fractionComplete: 1)
        emit(.downloadProgress(fractionComplete: 1, bytesWritten: Int64(update.asset.size), bytesTotal: Int64(update.asset.size)))
        return DownloadedUpdate(update: update, archiveURL: archiveURL, tempDirectory: tempDirectory)
    }

    public func verify(_ downloaded: DownloadedUpdate) async throws -> VerifiedUpdate {
        state = .verifying(downloaded.update)
        emit(.verificationStarted)
        let verifier = self.verifier
        do {
            // Extraction (`ditto`/`hdiutil`) and verification (`codesign`/`spctl`) shell
            // out and block for seconds — run them off the main actor so the UI stays live.
            let (appURL, report) = try await Task.detached(priority: .userInitiated) {
                let extractedDirectory = downloaded.tempDirectory.appendingPathComponent("extracted", isDirectory: true)
                let appURL = try ArchiveExtractor.extractApp(fromArchiveAt: downloaded.archiveURL, into: extractedDirectory)
                let report = try verifier.verify(appAt: appURL)
                return (appURL, report)
            }.value
            let verified = VerifiedUpdate(update: downloaded.update, extractedAppURL: appURL, tempDirectory: downloaded.tempDirectory, verificationReport: report)
            currentVerified = verified
            state = .readyToInstall(downloaded.update)
            emit(.verificationFinished(.success(report)))
            return verified
        } catch let error as SunshineError {
            state = .error(error)
            emit(.verificationFinished(.failure(error)))
            throw error
        } catch {
            let wrapped = SunshineError.extractionFailed(underlying: error)
            state = .error(wrapped)
            emit(.verificationFinished(.failure(wrapped)))
            throw wrapped
        }
    }

    public func install(_ verified: VerifiedUpdate) async throws -> Never {
        state = .installing
        emit(.installStarted)
        let session = InstallSession(bundleIdentifier: bundleIdentifier, verifier: verifier)
        let installURL = self.installURL
        do {
            emit(.willRelaunch)
            // Re-verification and the bundle swap also block on subprocesses; keep them
            // off the main actor so the sheet can show its "installing" state.
            try await Task.detached(priority: .userInitiated) {
                try await session.install(verified, installURL: installURL)
            }.value
        } catch let error as SunshineError {
            state = .error(error)
            emit(.installFailed(error, rolledBack: true))
            throw error
        } catch {
            let wrapped = SunshineError.rollbackFailed(underlying: error)
            state = .error(wrapped)
            emit(.installFailed(wrapped, rolledBack: true))
            throw wrapped
        }
        delegate?.updaterDidFinishInstalling(self)
        exit(0)
    }

    /// End-to-end convenience path. `silently` skips the `.readyToInstall` pause for a
    /// single manually-triggered call — it does not change the persistent
    /// `automationLevel` preference used by the scheduled background-check loop.
    public func checkDownloadVerifyAndInstall(silently: Bool) async throws {
        let result = await checkForUpdates()
        guard case .updateAvailable(let update) = result else { return }
        let downloaded = try await download(update)
        let verified = try await verify(downloaded)
        if silently || configuration.automationLevel == .autoDownloadAndInstall {
            try await install(verified)
        }
    }

    public func skip(_ update: Update) {
        store.skip(update)
    }

    /// Clears a previously skipped version and any active "remind me later" timer, so the
    /// update becomes eligible again on the next check (e.g. when the user chooses to view
    /// an update they'd earlier skipped or deferred).
    public func clearSkippedVersion() {
        store.clearSkip()
        store.clearRemindLater()
    }

    public func remindLater(_ update: Update, for interval: TimeInterval = 24 * 60 * 60) {
        store.remindLater(update, for: interval)
    }

    /// Must be called once, as early as possible in the host app's startup (e.g.
    /// `applicationDidFinishLaunching`), so a pending relaunch handshake from a previous
    /// install can be confirmed.
    public static func confirmSuccessfulRelaunchIfNeeded() {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        RelaunchCoordinator.confirmSuccessfulRelaunchIfNeeded(bundleIdentifier: bundleID)
    }

    // MARK: - Automatic scheduling

    private func startAutomaticChecking() {
        schedulingTask?.cancel()
        schedulingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let baseInterval = self.configuration.checkInterval ?? 3600
                let lastCheck = self.store.lastCheckDate()
                let interval = self.store.nextCheckInterval(baseInterval: baseInterval)
                let elapsed = lastCheck.map { Date().timeIntervalSince($0) } ?? .infinity
                let wait = max(0, interval - elapsed)
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                let result = await self.checkForUpdates()
                let automationLevel = self.configuration.automationLevel
                if case .updateAvailable = result, automationLevel != .manual {
                    try? await self.checkDownloadVerifyAndInstall(silently: false)
                }
            }
        }
    }

    private func isSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private func emit(_ event: UpdateEvent) {
        eventContinuation?.yield(event)
    }
}
