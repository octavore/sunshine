public enum UpdateCheckResult: Sendable {
    case updateAvailable(Update)
    case noUpdateAvailable(latestKnown: Update?)
    case failed(SunshineError)
}
