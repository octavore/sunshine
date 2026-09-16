import Foundation
import Testing

@testable import SunshineCore

@Suite struct SkipAndRemindStoreTests {
  /// A store backed by its own throwaway defaults domain, so tests never touch the
  /// user's real preferences or each other's.
  private func makeStore() -> (SkipAndRemindStore, UserDefaults, String) {
    let suiteName = "com.sunshine.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (
      SkipAndRemindStore(bundleIdentifier: "test.app", defaults: defaults), defaults, suiteName
    )
  }

  private func update(tag: String) -> Update {
    Update(
      release: GitHubRelease(tagName: tag),
      asset: GitHubAsset(
        name: "App-\(tag).zip", browserDownloadURL: URL(string: "https://example.com/\(tag).zip")!,
        size: 1)
    )
  }

  @Test func remindLaterSuppressesOnlyTheDeferredVersion() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.remindLater(update(tag: "2.0.0"), for: 3600)

    #expect(store.isRemindingLater(about: update(tag: "2.0.0")))
    // A release published during the deferral is a different version, so it is offered.
    #expect(!store.isRemindingLater(about: update(tag: "2.1.0")))
    #expect(store.isRemindingLater())
    #expect(store.remindLaterVersion() == "2.0.0")
  }

  @Test func elapsedDeferralStopsSuppressing() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.remindLater(update(tag: "2.0.0"), for: -1)

    #expect(!store.isRemindingLater())
    #expect(!store.isRemindingLater(about: update(tag: "2.0.0")))
    #expect(store.remindLaterVersion() == nil)
  }

  @Test func clearRemindLaterDropsBothTheDeadlineAndTheVersion() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.remindLater(update(tag: "2.0.0"), for: 3600)
    store.clearRemindLater()

    #expect(!store.isRemindingLater())
    #expect(store.remindLaterVersion() == nil)
    // A second deferral after a clear still works.
    store.remindLater(update(tag: "2.1.0"), for: 3600)
    #expect(store.isRemindingLater(about: update(tag: "2.1.0")))
  }

  @Test func deadlineWithoutARecordedVersionDoesNotSuppress() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    // What a deferral written by an older version of Sunshine looks like on disk.
    defaults.set(Date().addingTimeInterval(3600), forKey: "com.sunshine.test.app.remindAfter")

    #expect(!store.isRemindingLater())
    #expect(!store.isRemindingLater(about: update(tag: "2.0.0")))
  }

  @Test func skipSuppressesOnlyTheSkippedVersion() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.skip(update(tag: "2.0.0"))
    #expect(store.skippedVersion() == "2.0.0")

    store.clearSkip()
    #expect(store.skippedVersion() == nil)
  }

  @Test func failedChecksBackOffExponentiallyAndResetOnSuccess() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(store.nextCheckInterval(baseInterval: 100) == 100)

    store.recordCheckAttempt(succeeded: false, baseInterval: 100)
    #expect(store.nextCheckInterval(baseInterval: 100) == 100)
    store.recordCheckAttempt(succeeded: false, baseInterval: 100)
    #expect(store.nextCheckInterval(baseInterval: 100) == 200)

    // The backoff is capped at 16x the base interval.
    for _ in 0..<10 {
      store.recordCheckAttempt(succeeded: false, baseInterval: 100)
    }
    #expect(store.nextCheckInterval(baseInterval: 100) == 1600)

    store.recordCheckAttempt(succeeded: true, baseInterval: 100)
    #expect(store.nextCheckInterval(baseInterval: 100) == 100)
  }
}
