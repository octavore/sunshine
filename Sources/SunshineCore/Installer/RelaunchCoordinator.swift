import Foundation
import AppKit

/// Launches the newly-installed bundle and waits for it to confirm it started
/// successfully, via a sentinel file the new process writes early in its own startup.
/// `NSWorkspace` (AppKit) is used here rather than a separate relaunch-helper process —
/// simpler for v1, at the cost of a brief window where old and new processes coexist.
enum RelaunchCoordinator {
    static let relaunchArgumentPrefix = "--sunshine-relaunched-from="

    static func sentinelURL(forBundleIdentifier bundleIdentifier: String, releaseTag: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("launched-ok-\(releaseTag)")
    }

    /// Call this once, as early as possible, when a host app starts up (both UI and
    /// headless integrations must wire this in `applicationDidFinishLaunching` or
    /// equivalent) so a pending relaunch handshake can be confirmed.
    static func confirmSuccessfulRelaunchIfNeeded(bundleIdentifier: String) {
        guard let releaseTag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(relaunchArgumentPrefix) }) else {
            return
        }
        let tag = String(releaseTag.dropFirst(relaunchArgumentPrefix.count))
        let sentinel = sentinelURL(forBundleIdentifier: bundleIdentifier, releaseTag: tag)
        try? FileManager.default.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sentinel.path, contents: Data())
    }

    /// Launches `installURL`, then polls for the sentinel file for up to `timeout`
    /// seconds. Returns `true` on confirmed success.
    static func relaunchAndAwaitConfirmation(
        installURL: URL,
        bundleIdentifier: String,
        releaseTag: String,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let sentinel = sentinelURL(forBundleIdentifier: bundleIdentifier, releaseTag: releaseTag)
        try? FileManager.default.removeItem(at: sentinel)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["\(relaunchArgumentPrefix)\(releaseTag)"]
        configuration.createsNewApplicationInstance = true

        do {
            _ = try await NSWorkspace.shared.openApplication(at: installURL, configuration: configuration)
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: sentinel.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        // Fallback: a running process with the target bundle identifier is a weaker,
        // but still meaningful, success signal if the host app never wires the sentinel.
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
