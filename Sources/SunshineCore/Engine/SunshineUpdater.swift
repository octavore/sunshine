import Combine
import Foundation

/// Core update engine.
/// It checks GitHub Releases, downloads, verifies against the running app's code signature,
/// and swaps the new bundle into place. It works headlessly or through `SunshineUI`'s
/// `SunshineUpdaterUIController`.
@MainActor
public final class SunshineUpdater: ObservableObject {
  @Published public private(set) var state: UpdateState = .idle

  public weak var delegate: (any SunshineUpdaterDelegate)?

  /// Action that ends the host process once the relaunch script is waiting.
  /// The default suits headless callers. `SunshineUI` replaces it with `NSApp.terminate(nil)`,
  /// so the app delegate, autosave, and unsaved-changes prompts run first.
  public var terminate: @MainActor () -> Void = { exit(0) }

  /// Wait after `terminate()` before termination is assumed refused and the script is
  /// stood down. Refusal includes an app delegate returning `.terminateCancel` and a user
  /// dismissing an unsaved-changes sheet.
  var terminationGracePeriod: TimeInterval = 20

  private var configuration: SunshineConfiguration
  private let client: any ReleasesProviding
  private let verifier: UpdateVerifier
  private let store: SkipAndRemindStore
  private let preferencesStore: UpdatePreferencesStore
  private let bundleIdentifier: String
  private let installURL: URL

  private let eventContinuation: AsyncStream<UpdateEvent>.Continuation

  /// Progress events, as an alternative to ``SunshineUpdaterDelegate``.
  ///
  /// This stream has a single consumer. It is one `AsyncStream` shared by every reader of
  /// this property. It is not a broadcast. A second `for await` loop competes with the
  /// first, and each event goes to whichever loop is waiting. Iterate it from exactly one
  /// place. Use the delegate if more than one part of the app needs to observe.
  ///
  /// The stream starts at `init`, so events emitted before anything starts iterating are
  /// buffered. The buffer holds the newest ``eventBufferSize`` events. A consumer that
  /// stops iterating cannot grow the buffer without bound, but it misses the oldest events.
  public let events: AsyncStream<UpdateEvent>

  /// Number of unconsumed events the stream holds before it discards the oldest.
  public static let eventBufferSize = 256

  /// Update most recently verified by ``verify(_:)``, or `nil` if none has been.
  /// Pass it to ``install(_:)`` to install without downloading again.
  public private(set) var verifiedUpdate: VerifiedUpdate?

  private var schedulingTask: Task<Void, Never>?
  private var downloadTask: Task<(URL, URLResponse), any Error>?

  /// - Parameter releasesProvider: Source of release data. Defaults to a real
  ///   `GitHubReleasesClient`. Pass a `StaticReleasesProvider` to use a fixed list of
  ///   releases, e.g. for SwiftUI previews, examples, or tests.
  public init(
    configuration: SunshineConfiguration, releasesProvider: (any ReleasesProviding)? = nil
  ) {
    // Create the stream here instead of lazily on first read. Events emitted before the
    // host subscribes are then buffered. The background check loop starts in this
    // initializer, so such events are possible.
    var continuation: AsyncStream<UpdateEvent>.Continuation!
    self.events = AsyncStream(bufferingPolicy: .bufferingNewest(Self.eventBufferSize)) {
      continuation = $0
    }
    self.eventContinuation = continuation

    self.configuration = configuration
    self.client = releasesProvider ?? GitHubReleasesClient(token: configuration.githubToken)
    self.verifier = UpdateVerifier(requireNotarization: configuration.requireNotarization)
    let bundleID = Bundle.main.bundleIdentifier ?? "\(configuration.owner).\(configuration.repo)"
    self.bundleIdentifier = bundleID
    self.installURL = configuration.installLocation ?? Bundle.main.bundleURL
    self.store = SkipAndRemindStore(bundleIdentifier: bundleID)
    self.preferencesStore = UpdatePreferencesStore(bundleIdentifier: bundleID)

    if let savedAutoCheck = preferencesStore.automaticallyCheckForUpdates {
      self.configuration.checkInterval =
        savedAutoCheck ? (configuration.checkInterval ?? 3600) : nil
    }
    if let savedLevel = preferencesStore.automationLevel {
      self.configuration.automationLevel = savedLevel
    }
    if let savedPrereleases = preferencesStore.allowPrereleases {
      self.configuration.allowPrereleases = savedPrereleases
    }

    // Confirm a pending relaunch handshake. The host app does not need to call
    // `confirmSuccessfulRelaunchIfNeeded()` itself. This does nothing unless
    // RelaunchCoordinator started the process.
    RelaunchCoordinator.confirmSuccessfulRelaunchIfNeeded(
      bundleIdentifier: bundleID, notifyOnSuccess: configuration.notifyOnSuccessfulUpdate)

    // Recovery must run before the sweep. The sweep can delete the aside bundle that
    // recovery needs to move back.
    InstallSession.recoverInterruptedInstall(bundleIdentifier: bundleID)
    InstallSession.sweepStaleAsideBundles(near: installURL)

    if self.configuration.checkInterval != nil {
      startAutomaticChecking()
    }
  }

  // MARK: - Live settings (for `SunshineUpdateSettingsView`)

  /// Whether the background check loop is running.
  /// Setting this persists the preference and starts or stops the loop immediately.
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

  /// Whether a found update downloads, verifies, and installs unattended.
  /// Setting this persists the preference immediately.
  public var automationLevel: UpdateAutomationLevel {
    get { configuration.automationLevel }
    set {
      objectWillChange.send()
      configuration.automationLevel = newValue
      preferencesStore.automationLevel = newValue
    }
  }

  /// Whether prerelease GitHub releases are eligible updates.
  /// Setting this persists the preference immediately.
  public var allowPrereleases: Bool {
    get { configuration.allowPrereleases }
    set {
      objectWillChange.send()
      configuration.allowPrereleases = newValue
      preferencesStore.allowPrereleases = newValue
    }
  }

  /// Time of the most recent check, successful or not.
  public var lastCheckDate: Date? { store.lastCheckDate() }

  /// GitHub releases page of the repository.
  public var releasesPageURL: URL? {
    URL(string: "https://github.com/\(configuration.owner)/\(configuration.repo)/releases")
  }

  /// Release tag the user skipped via ``skip(_:)``, or `nil` if none.
  /// A check treats this version as "up to date". ``clearSkippedVersion()`` reverses it.
  public var skippedVersion: String? { store.skippedVersion() }

  /// Whether a "remind me later" deferral is active.
  /// Only the deferred version is suppressed. A newer release published during the
  /// deferral is still offered. ``clearSkippedVersion()`` or the end of the interval
  /// clears the deferral.
  public var isRemindingLater: Bool { store.isRemindingLater() }

  /// Release tag the user deferred via ``remindLater(_:for:)``, or `nil` if there is no
  /// active deferral.
  public var remindLaterVersion: String? { store.remindLaterVersion() }

  // MARK: - Headless / programmatic API

  public func checkForUpdates() async -> UpdateCheckResult {
    emit(.checkStarted)
    state = .checking

    guard !isSandboxed() else {
      let result = UpdateCheckResult.failed(.sandboxedAppUnsupported)
      fail(.sandboxedAppUnsupported)
      emit(.checkFinished(result))
      return result
    }

    do {
      let releases: [GitHubRelease]
      if configuration.allowPrereleases {
        releases = try await client.fetchRecentReleases(
          owner: configuration.owner, repo: configuration.repo
        )
        .filter { !$0.draft }
        .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
      } else {
        releases = [
          try await client.fetchLatestRelease(owner: configuration.owner, repo: configuration.repo)
        ]
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
        let result = UpdateCheckResult.noUpdateAvailable(
          latestKnown: nil, releaseURL: latest.htmlURL)
        emit(.checkFinished(result))
        return result
      }

      let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String
      guard
        let asset = AssetMatcher.select(
          from: latest.assets, matching: configuration.assetMatcher, bundleName: bundleName)
      else {
        let result = UpdateCheckResult.failed(.noMatchingAsset)
        fail(.noMatchingAsset)
        emit(.checkFinished(result))
        return result
      }

      var update = Update(release: latest, asset: asset)
      update = await aggregatingReleaseNotes(
        for: update, knownReleases: releases, runningVersion: runningVersion)

      if store.skippedVersion() == update.id || store.isRemindingLater(about: update) {
        state = .upToDate
        let result = UpdateCheckResult.noUpdateAvailable(
          latestKnown: update, releaseURL: update.htmlURL)
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
      fail(error)
      let result = UpdateCheckResult.failed(error)
      emit(.checkFinished(result))
      return result
    } catch {
      store.recordCheckAttempt(succeeded: false, baseInterval: configuration.checkInterval ?? 3600)
      let wrapped = SunshineError.network(underlying: error)
      fail(wrapped)
      let result = UpdateCheckResult.failed(wrapped)
      emit(.checkFinished(result))
      return result
    }
  }

  /// Combine release notes of every release newer than `runningVersion`, newest first.
  /// A user who skipped several versions sees all of them.
  ///
  /// The stable path checks a single release. Intermediate releases are fetched here, and
  /// only after an update is found. A check that finds nothing costs one API call. A failed
  /// fetch falls back to the update's own notes and does not fail the check.
  private func aggregatingReleaseNotes(
    for update: Update, knownReleases: [GitHubRelease], runningVersion: AppVersion
  ) async -> Update {
    var candidates = knownReleases
    if candidates.count <= 1 {
      let recent = try? await client.fetchRecentReleases(
        owner: configuration.owner, repo: configuration.repo)
      if let recent {
        candidates = recent.filter {
          !$0.draft && (configuration.allowPrereleases || !$0.prerelease)
        }
      }
    }

    guard
      let combined = ReleaseNotesAggregation.combinedNotes(
        for: update, candidates: candidates, runningVersion: runningVersion
      )
    else { return update }

    return Update(
      release: GitHubRelease(
        tagName: update.id, name: nil, body: combined, draft: false,
        prerelease: update.isPrerelease, publishedAt: update.publishedAt,
        htmlURL: update.htmlURL, assets: [update.asset]
      ), asset: update.asset)
  }

  public func download(_ update: Update) async throws -> DownloadedUpdate {
    state = .downloading(update, fractionComplete: 0)
    let tempDirectory = SunshineCache.updateDirectory(
      forBundleIdentifier: bundleIdentifier, releaseTag: update.id)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    // Sanitize the asset name from the API response before using it as a filename.
    // The extension is preserved. The extractor selects its method by extension.
    let archiveURL = tempDirectory.appendingPathComponent(
      SunshineCache.safeComponent(update.asset.name))

    do {
      let progressDelegate = DownloadProgressForwarder { [weak self] fraction in
        Task { @MainActor in
          guard let self else { return }
          self.state = .downloading(update, fractionComplete: fraction)
          self.emit(
            .downloadProgress(
              fractionComplete: fraction,
              bytesWritten: Int64(Double(update.asset.size) * fraction),
              bytesTotal: Int64(update.asset.size)))
        }
      }
      let request = URLRequest(url: update.asset.browserDownloadURL)
      // Stored for `cancelDownload()`. Cancelling the task cancels the URLSession transfer.
      let task = Task {
        try await URLSession.shared.download(for: request, delegate: progressDelegate)
      }
      downloadTask = task
      defer { downloadTask = nil }

      let (downloadedURL, _) = try await task.value
      if FileManager.default.fileExists(atPath: archiveURL.path) {
        try FileManager.default.removeItem(at: archiveURL)
      }
      try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
    } catch {
      // A user-initiated cancel returns to the review and is not reported as a failure.
      // The update is still available.
      guard !Self.isCancellation(error) else {
        state = .updateAvailable(update)
        throw SunshineError.cancelled
      }
      let wrapped = SunshineError.downloadFailed(underlying: error)
      fail(wrapped)
      throw wrapped
    }

    state = .downloading(update, fractionComplete: 1)
    emit(
      .downloadProgress(
        fractionComplete: 1, bytesWritten: Int64(update.asset.size),
        bytesTotal: Int64(update.asset.size)))
    return DownloadedUpdate(update: update, archiveURL: archiveURL, tempDirectory: tempDirectory)
  }

  /// Whether a download is in flight and can be cancelled.
  /// Verification and install are not cancellable. Both are short, and abandoning a swap
  /// partway is worse than finishing it.
  public var isDownloadCancellable: Bool { downloadTask != nil }

  /// Cancel an in-flight download.
  /// ``download(_:)`` then throws ``SunshineError/cancelled`` and the state returns to
  /// `.updateAvailable`, so the user can start it again. Does nothing if no download is
  /// running.
  public func cancelDownload() {
    downloadTask?.cancel()
  }

  /// Whether `error` is a cancellation.
  /// URLSession reports a cancelled transfer as `URLError.cancelled`. Cancelling before the
  /// request starts throws `CancellationError`.
  private static func isCancellation(_ error: any Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
  }

  public func verify(_ downloaded: DownloadedUpdate) async throws -> VerifiedUpdate {
    state = .verifying(downloaded.update)
    emit(.verificationStarted)
    let verifier = self.verifier
    do {
      // Extraction (`ditto`/`hdiutil`) and verification (`codesign`/`spctl`) run external
      // tools and block for seconds. They run off the main actor so the UI stays responsive.
      let (appURL, report) = try await Task.detached(priority: .userInitiated) {
        let extractedDirectory = downloaded.tempDirectory.appendingPathComponent(
          "extracted", isDirectory: true)
        let appURL = try ArchiveExtractor.extractApp(
          fromArchiveAt: downloaded.archiveURL, into: extractedDirectory)
        let report = try verifier.verify(appAt: appURL)
        return (appURL, report)
      }.value
      let verified = VerifiedUpdate(
        update: downloaded.update, extractedAppURL: appURL, tempDirectory: downloaded.tempDirectory,
        verificationReport: report)
      verifiedUpdate = verified
      state = .readyToInstall(downloaded.update)
      emit(.verificationFinished(.success(report)))
      return verified
    } catch let error as SunshineError {
      fail(error)
      emit(.verificationFinished(.failure(error)))
      throw error
    } catch {
      let wrapped = SunshineError.extractionFailed(underlying: error)
      fail(wrapped)
      emit(.verificationFinished(.failure(wrapped)))
      throw wrapped
    }
  }

  /// Stage the update, hand the swap to a detached script, and terminate this process.
  /// On success the process is expected to be gone. A throw means nothing was moved.
  ///
  /// The swap, relaunch, and any rollback happen after this process exits. Their outcome
  /// is not reported through `events`. Only failures raised before the script is spawned
  /// produce `.installFailed`.
  public func install(_ verified: VerifiedUpdate) async throws {
    state = .installing
    emit(.installStarted)
    let session = InstallSession(bundleIdentifier: bundleIdentifier, verifier: verifier)
    let installURL = self.installURL
    do {
      // Re-verification runs `codesign` and `spctl` and blocks for seconds. It runs off the
      // main actor so the sheet can show its "installing" state.
      try await Task.detached(priority: .userInitiated) {
        try await session.install(verified, installURL: installURL)
      }.value
    } catch let error as SunshineError {
      fail(error)
      emit(.installFailed(error))
      throw error
    } catch {
      let wrapped = SunshineError.relaunchFailed(underlying: error)
      fail(wrapped)
      emit(.installFailed(wrapped))
      throw wrapped
    }

    emit(.willRelaunch)
    delegate?.updaterDidFinishInstalling(self)

    terminate()

    // Reached only if termination was refused. The script is still waiting on this
    // process. Stand it down so it does not swap the bundle under a live app if this
    // process exits later.
    Task { [terminationGracePeriod] in
      try? await Task.sleep(nanoseconds: UInt64(terminationGracePeriod * 1_000_000_000))
      self.abortPendingInstall()
    }
  }

  /// Cancel an install whose script is spawned but has not acted yet.
  /// The current bundle stays in place. Call this if the app declines to terminate after
  /// `install()`, e.g. `applicationShouldTerminate` returns `.terminateCancel`.
  /// `install()` also calls this after its grace period elapses.
  ///
  /// This takes effect only while this process is alive. The script ignores the signal
  /// once the host exits, so a termination that is cancelled and later completed still
  /// updates. The script owns the breadcrumb file for the same reason, so this does not
  /// remove it.
  public func abortPendingInstall() {
    RelaunchCoordinator.abortPendingInstall(bundleIdentifier: bundleIdentifier)
    if case .installing = state {
      fail(.cancelled)
      emit(.installFailed(.cancelled))
    }
  }

  /// Check, download, verify, and install in one call.
  /// `silently` skips the `.readyToInstall` pause for this call only. It does not change
  /// the `automationLevel` preference used by the background check loop.
  public func checkDownloadVerifyAndInstall(silently: Bool) async throws {
    let result = await checkForUpdates()
    guard case .updateAvailable(let update) = result else { return }
    try await downloadVerifyAndInstall(update, silently: silently)
  }

  /// Download and verify `update`, then install it if `silently` is set or
  /// `automationLevel` is `.autoDownloadAndInstall`.
  private func downloadVerifyAndInstall(_ update: Update, silently: Bool) async throws {
    let downloaded = try await download(update)
    let verified = try await verify(downloaded)
    if silently || configuration.automationLevel == .autoDownloadAndInstall {
      try await install(verified)
    }
  }

  public func skip(_ update: Update) {
    store.skip(update)
  }

  /// Clear a skipped version and any active "remind me later" timer.
  /// The update is eligible again on the next check, e.g. if the user chooses to view an
  /// update they skipped or deferred.
  public func clearSkippedVersion() {
    store.clearSkip()
    store.clearRemindLater()
  }

  public func remindLater(_ update: Update, for interval: TimeInterval = 24 * 60 * 60) {
    store.remindLater(update, for: interval)
  }

  // MARK: - Moving to Applications

  /// Whether the app runs from a location where it cannot update itself.
  /// Such locations include an App Translocation path, a read-only volume, and any folder
  /// the user cannot write to.
  public var shouldOfferMoveToApplications: Bool {
    InstallLocationChecker.issue(for: installURL) != nil
      || !InstallLocationChecker.isWritable(installURL)
  }

  /// Copy the app into `/Applications`, or `~/Applications` if that is not writable.
  /// Launch the copy and terminate this process. The original bundle is left in place. A
  /// throw means the original app is unchanged and continues to run.
  public func moveToApplicationsAndRelaunch() throws {
    do {
      let destination = try ApplicationMover.copy(appAt: installURL)
      try ApplicationMover.launch(destination)
    } catch {
      let wrapped = SunshineError.moveToApplicationsFailed(underlying: error)
      delegate?.updater(self, didFailWithError: wrapped)
      throw wrapped
    }
    terminate()
  }

  /// Confirm a pending relaunch handshake from a previous install.
  /// Call this once, as early as possible in host app startup, e.g. in
  /// `applicationDidFinishLaunching`.
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
        if case .updateAvailable(let update) = result {
          if automationLevel == .manual {
            if self.configuration.notifyOnUpdateAvailable {
              UpdateNotifications.updateAvailable(releaseTag: update.id)
            }
          } else {
            do {
              try await self.downloadVerifyAndInstall(update, silently: false)
            } catch {
              if self.configuration.notifyOnUpdateFailure {
                UpdateNotifications.updateFailed(message: Self.message(for: error))
              }
            }
          }
        }
      }
    }
  }

  private static func message(for error: any Error) -> String {
    (error as? SunshineError)?.description ?? error.localizedDescription
  }

  private func isSandboxed() -> Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }

  /// Record `error` in `state` and report it to the delegate.
  private func fail(_ error: SunshineError) {
    state = .error(error)
    delegate?.updater(self, didFailWithError: error)
  }

  private func emit(_ event: UpdateEvent) {
    eventContinuation.yield(event)
  }

  deinit {
    // End any `for await` loop over `events`. Otherwise it stays suspended.
    eventContinuation.finish()
  }
}
