public enum UpdateEvent: Sendable {
  case checkStarted
  case checkFinished(UpdateCheckResult)
  case downloadProgress(fractionComplete: Double, bytesWritten: Int64, bytesTotal: Int64)
  case verificationStarted
  case verificationFinished(Result<VerificationReport, SunshineError>)
  case installStarted
  case willRelaunch
  /// Install failed before the relaunch script moved anything, or was aborted.
  case installFailed(SunshineError)
}

/// Optional callback-style alternative to `SunshineUpdater.events`, for consumers that
/// prefer delegation to `AsyncStream`. The updater calls it directly, independently of
/// `events`. `updater(_:didFailWithError:)` reports every failure that sets
/// `UpdateState.error`, except a cancelled download.
public protocol SunshineUpdaterDelegate: AnyObject, Sendable {
  func updater(_ updater: SunshineUpdater, didFindUpdate update: Update)
  func updater(_ updater: SunshineUpdater, didFailWithError error: SunshineError)
  func updaterDidFinishInstalling(_ updater: SunshineUpdater)
}
