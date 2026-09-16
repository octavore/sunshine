public enum UpdateEvent: Sendable {
  case checkStarted
  case checkFinished(UpdateCheckResult)
  case downloadProgress(fractionComplete: Double, bytesWritten: Int64, bytesTotal: Int64)
  case verificationStarted
  case verificationFinished(Result<VerificationReport, SunshineError>)
  case installStarted
  case willRelaunch
  case installFailed(SunshineError, rolledBack: Bool)
}

/// Optional callback-style adapter over `SunshineUpdater.events`, for consumers that
/// prefer delegation to `AsyncStream`. It is not a separate code path: implementations
/// observe the same event stream.
public protocol SunshineUpdaterDelegate: AnyObject, Sendable {
  func updater(_ updater: SunshineUpdater, didFindUpdate update: Update)
  func updater(_ updater: SunshineUpdater, didFailWithError error: SunshineError)
  func updaterDidFinishInstalling(_ updater: SunshineUpdater)
}
