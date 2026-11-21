import Foundation

/// Persisted "skip this version" and "remind me later" decisions.
/// Also stores the last check timestamp and backoff interval used for rate limiting.
struct SkipAndRemindStore {
  private let defaults: UserDefaults
  private let keyPrefix: String

  init(bundleIdentifier: String, defaults: UserDefaults = .standard) {
    self.keyPrefix = "com.sunshine.\(bundleIdentifier)."
    self.defaults = defaults
  }

  private var skippedVersionKey: String { keyPrefix + "skippedVersion" }
  private var remindAfterKey: String { keyPrefix + "remindAfter" }
  private var remindVersionKey: String { keyPrefix + "remindVersion" }
  private var lastCheckKey: String { keyPrefix + "lastCheck" }
  private var backoffIntervalKey: String { keyPrefix + "backoffInterval" }

  func skippedVersion() -> String? {
    defaults.string(forKey: skippedVersionKey)
  }

  func skip(_ update: Update) {
    defaults.set(update.id, forKey: skippedVersionKey)
  }

  func clearSkip() {
    defaults.removeObject(forKey: skippedVersionKey)
  }

  /// Defer `update` only.
  /// The version is recorded with the deadline, so a release published during the deferral
  /// is still offered.
  func remindLater(_ update: Update, for interval: TimeInterval) {
    defaults.set(Date().addingTimeInterval(interval), forKey: remindAfterKey)
    defaults.set(update.id, forKey: remindVersionKey)
  }

  /// Deferred version, or `nil` if there is no deferral or it has elapsed.
  /// A deadline written before the version was recorded also reads as `nil`. The update
  /// is then shown.
  func remindLaterVersion() -> String? {
    guard let date = defaults.object(forKey: remindAfterKey) as? Date, date > Date() else {
      return nil
    }
    return defaults.string(forKey: remindVersionKey)
  }

  /// Whether a deferral is active for any version.
  func isRemindingLater() -> Bool {
    remindLaterVersion() != nil
  }

  /// Whether `update` is the deferred version and the deferral has not elapsed.
  func isRemindingLater(about update: Update) -> Bool {
    remindLaterVersion() == update.id
  }

  func clearRemindLater() {
    defaults.removeObject(forKey: remindAfterKey)
    defaults.removeObject(forKey: remindVersionKey)
  }

  func lastCheckDate() -> Date? {
    defaults.object(forKey: lastCheckKey) as? Date
  }

  func recordCheckAttempt(succeeded: Bool, baseInterval: TimeInterval) {
    defaults.set(Date(), forKey: lastCheckKey)
    if succeeded {
      defaults.removeObject(forKey: backoffIntervalKey)
    } else {
      let current = defaults.double(forKey: backoffIntervalKey)
      let next = current > 0 ? min(current * 2, baseInterval * 16) : baseInterval
      defaults.set(next, forKey: backoffIntervalKey)
    }
  }

  /// Interval to wait before the next automatic check.
  /// Repeated failures apply exponential backoff.
  func nextCheckInterval(baseInterval: TimeInterval) -> TimeInterval {
    let backoff = defaults.double(forKey: backoffIntervalKey)
    return backoff > 0 ? backoff : baseInterval
  }
}
