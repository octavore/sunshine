import Foundation

public enum UpdateCheckResult: Sendable {
    case updateAvailable(Update)
    /// `releaseURL` is the GitHub releases page for the version that was checked against,
    /// even when `latestKnown` is `nil` (e.g. no asset in that release matched this machine).
    case noUpdateAvailable(latestKnown: Update?, releaseURL: URL? = nil)
    case failed(SunshineError)
}
