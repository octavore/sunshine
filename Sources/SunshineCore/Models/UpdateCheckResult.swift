import Foundation

public enum UpdateCheckResult: Sendable {
  case updateAvailable(Update)
  /// `releaseURL` is the GitHub releases page of the checked version.
  /// It is set even if `latestKnown` is `nil`, e.g. if no asset matched this machine.
  case noUpdateAvailable(latestKnown: Update?, releaseURL: URL? = nil)
  case failed(SunshineError)
}
