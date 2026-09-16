import Combine
import Foundation

/// The core update engine: checks GitHub Releases, downloads, verifies against the
/// running app's code signature, and swaps the new bundle into place. Usable headlessly
/// (no UI import) or driven by `SunshineUI`'s `SunshineUpdaterUIController`.
@MainActor
public final class SunshineUpdater: ObservableObject {
  @Published public private(set) var state: UpdateState = .idle

  public weak var delegate: (any SunshineUpdaterDelegate)?

  /// How the host process ends itself once the relaunch script is waiting. The default
  /// suits headless callers; `SunshineUI` replaces it with `NSApp.terminate(nil)` so the
  /// app delegate, autosave, and unsaved-changes prompts all run first.
  public var terminate: @MainActor () -> Void = { exit(0) }

  /// How long to wait after `terminate()` before assuming termination was refused (an
  /// app delegate returning `.terminateCancel`, an unsaved-changes sheet the user
  /// dismisses) and standing the script down.
  var terminationGracePeriod: TimeInterval = 20

  private var configuration: SunshineConfiguration
  private let client: any ReleasesProviding
  private let verifier: UpdateVerifier
  private let store: SkipAndRemindStore
  private let preferencesStore: UpdatePreferencesStore
  private let bundleIdentifier: String
  private let installURL: URL

  private let eventContinuation: AsyncStream<UpdateEvent>.Continuation

  /// Progress events, for a caller that prefers a stream to ``SunshineUpdaterDelegate``.
  ///
  /// This is a **single-consumer** stream. It is one `AsyncStream` shared by everyone who
  /// reads this property, not a broadcast: a second `for await` loop over it does not get
  /// its own copy, it competes with the first, and each event is delivered to whichever
  /// loop happens to be waiting. Iterate it from exactly one place, and use the delegate
  /// if more than one part of the app needs to observe.
  ///
  /// The stream is live from `init`, so events emitted before anything starts iterating
  /// are buffered rather than dropped. The buffer keeps the newest
  /// ``eventBufferSize`` events: a consumer that stops iterating without breaking the
  /// loop cannot grow it without bound, but it will miss the oldest events it skipped.
  public let events: AsyncStream<UpdateEvent>

  /// How many unconsumed events the stream holds before it starts discarding the oldest.
  public static let eventBufferSize = 256

  /// The update most recently verified by ``verify(_:)``, or `nil` if none has been.
  /// Pass it to ``install(_:)`` to install without downloading again.
  public private(set) var verifiedUpdate: VerifiedUpdate?

  private var schedulingTask: Task<Void, Never>?
  private var downloadTask: Task<(URL, URLResponse), any Error>?

  /// - Parameter releasesProvider: Source of release data. Defaults to a real
  ///   `GitHubReleasesClient`; pass a `StaticReleasesProvider` to drive this updater from a
  ///   fixed list of releases instead, e.g. for SwiftUI previews, examples, or tests.
  public init(
    configuration: SunshineConfiguration, releasesProvider: (any ReleasesProviding)? = nil
  ) {
    // Built here rather than lazily on first read, so an event emitted before the host
    // subscribes is buffered instead of dropped. The background check loop starts in
    // this initializer, so that window is real.
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

    // Confirm a pending relaunch handshake automatically, so the host app does not
    // have to wire `confirmSuccessfulRelaunchIfNeeded()` itself. This is a no-op
    // unless the process was started by RelaunchCoordinator.
    RelaunchCoordinator.confirmSuccessfulRelaunchIfNeeded(bundleIdentifier: bundleID)

    // Recovery must run before the sweep, which would otherwise be free to delete the
    // very aside bundle recovery needs to move back.
    InstallSession.recoverInterruptedInstall(bundleIdentifier: bundleID)
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

  /// The repository's GitHub releases page, for linking out from settings UI.
  public var releasesPageURL: URL? {
    URL(string: "https://github.com/\(configuration.owner)/\(configuration.repo)/releases")
  }

  /// The release tag the user chose to skip via ``skip(_:)``, or `nil` if none.
  /// A check treats this version as "up to date"; ``clearSkippedVersion()`` undoes it.
  public var skippedVersion: String? { store.skippedVersion() }

  /// Whether a "remind me later" deferral is currently active. Only the deferred
  /// version is suppressed; a newer release published during the deferral is still
  /// offered. Cleared by ``clearSkippedVersion()`` or when the interval elapses.
  public var isRemindingLater: Bool { store.isRemindingLater() }

  /// The release tag the user deferred via ``remindLater(_:for:)``, or `nil` if there
  /// is no active deferral.
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

  /// Combines the release notes of every release newer than `runningVersion` (not just
  /// the latest), newest first, so a user who skipped several versions sees them all.
  ///
  /// The stable path checks a single release, so the intermediate ones are fetched here
  /// rather than up front, and only once an update has actually been found: a check that
  /// finds nothing still costs one API call. A failed fetch falls back to the update's
  /// own notes rather than failing the check.
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
    // The asset name comes from the API response, so it is sanitized before it becomes
    // a filename. The extension survives, which is what the extractor dispatches on.
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
      // Held so `cancelDownload()` has something to cancel. Cancelling the task
      // cancels the underlying URLSession transfer.
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
      // A user-initiated cancel returns to the review rather than reporting a
      // failure: nothing went wrong, and the update is still available.
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

  /// Whether a download is in flight and can still be cancelled. Verification and
  /// install are not cancellable: both are short, and abandoning a swap partway is
  /// worse than finishing it.
  public var isDownloadCancellable: Bool { downloadTask != nil }

  /// Cancels an in-flight download. ``download(_:)`` then throws
  /// ``SunshineError/cancelled`` and the state returns to `.updateAvailable`, so the
  /// user can start it again. Does nothing if no download is running.
  public func cancelDownload() {
    downloadTask?.cancel()
  }

  /// URLSession surfaces a cancelled transfer as `URLError.cancelled`, while cancelling
  /// before the request starts throws `CancellationError`.
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
      // Extraction (`ditto`/`hdiutil`) and verification (`codesign`/`spctl`) shell
      // out and block for seconds, so they run off the main actor to keep the UI responsive.
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

  /// Stages the update and hands the swap to a detached script, then terminates this
  /// process so the script can proceed. On success this does not return meaningfully;
  /// the process is expected to be gone. A throw means nothing was moved.
  ///
  /// Because the swap, relaunch, and any rollback happen after this process exits, their
  /// outcome cannot be reported back through `events`; only failures raised before the
  /// script is spawned produce `.installFailed`.
  public func install(_ verified: VerifiedUpdate) async throws {
    state = .installing
    emit(.installStarted)
    let session = InstallSession(bundleIdentifier: bundleIdentifier, verifier: verifier)
    let installURL = self.installURL
    do {
      // Re-verification shells out to `codesign`/`spctl` and blocks for seconds;
      // keep it off the main actor so the sheet can show its "installing" state.
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
    // process, so stand it down rather than let it swap the bundle out from under a
    // live app whenever this process eventually does exit.
    Task { [terminationGracePeriod] in
      try? await Task.sleep(nanoseconds: UInt64(terminationGracePeriod * 1_000_000_000))
      self.abortPendingInstall()
    }
  }

  /// Cancels an install whose script has already been spawned but has not yet acted,
  /// leaving the current bundle in place. Call this if the app declines to terminate
  /// (e.g. `applicationShouldTerminate` returns `.terminateCancel`) after `install()`.
  /// `install()` also does this automatically once its grace period elapses.
  ///
  /// This only takes effect while this process is alive: the script ignores the signal
  /// once the host exits, so a cancelled-then-completed termination still updates. The
  /// script owns the breadcrumb file for the same reason, and it is deliberately left
  /// in place here.
  public func abortPendingInstall() {
    RelaunchCoordinator.abortPendingInstall(bundleIdentifier: bundleIdentifier)
    if case .installing = state {
      fail(.cancelled)
      emit(.installFailed(.cancelled))
    }
  }

  /// End-to-end convenience path. `silently` skips the `.readyToInstall` pause for a
  /// single manually-triggered call. It does not change the persistent
  /// `automationLevel` preference used by the scheduled background-check loop.
  public func checkDownloadVerifyAndInstall(silently: Bool) async throws {
    let result = await checkForUpdates()
    guard case .updateAvailable(let update) = result else { return }
    try await downloadVerifyAndInstall(update, silently: silently)
  }

  /// Downloads and verifies `update`, then installs it if `silently` is set or
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
        if case .updateAvailable(let update) = result, automationLevel != .manual {
          try? await self.downloadVerifyAndInstall(update, silently: false)
        }
      }
    }
  }

  private func isSandboxed() -> Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }

  /// Records `error` in `state` and reports it to the delegate.
  private func fail(_ error: SunshineError) {
    state = .error(error)
    delegate?.updater(self, didFailWithError: error)
  }

  private func emit(_ event: UpdateEvent) {
    eventContinuation.yield(event)
  }

  deinit {
    // Ends any `for await` loop over `events` rather than leaving it suspended forever.
    eventContinuation.finish()
  }
}
