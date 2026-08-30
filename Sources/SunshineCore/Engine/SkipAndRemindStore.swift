import Foundation

/// Persists per-user "skip this version" / "remind me later" decisions and the last
/// successful/attempted check timestamps used for launch-time rate limiting and backoff.
struct SkipAndRemindStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(bundleIdentifier: String, defaults: UserDefaults = .standard) {
        self.keyPrefix = "com.sunshine.\(bundleIdentifier)."
        self.defaults = defaults
    }

    private var skippedVersionKey: String { keyPrefix + "skippedVersion" }
    private var remindAfterKey: String { keyPrefix + "remindAfter" }
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

    func remindLater(_ update: Update, for interval: TimeInterval) {
        defaults.set(Date().addingTimeInterval(interval), forKey: remindAfterKey)
    }

    func isRemindingLater() -> Bool {
        guard let date = defaults.object(forKey: remindAfterKey) as? Date else { return false }
        return date > Date()
    }

    func clearRemindLater() {
        defaults.removeObject(forKey: remindAfterKey)
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

    /// The effective interval to wait before the next automatic check, accounting for
    /// exponential backoff on repeated failures.
    func nextCheckInterval(baseInterval: TimeInterval) -> TimeInterval {
        let backoff = defaults.double(forKey: backoffIntervalKey)
        return backoff > 0 ? backoff : baseInterval
    }
}
