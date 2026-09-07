import Foundation

/// Owns the paths and the handshake shared by the host process and the relaunch script.
/// The swap and relaunch themselves happen in `RelaunchScript`, spawned detached so the
/// host can terminate normally first.
enum RelaunchCoordinator {
    static let relaunchArgumentPrefix = "--sunshine-relaunched-from="

    /// Both the script and the relaunched app derive this from the same raw tag, so the
    /// sanitizing has to happen here, in one place, or the handshake never matches.
    static func sentinelURL(forBundleIdentifier bundleIdentifier: String, releaseTag: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("launched-ok-\(SunshineCache.safeComponent(releaseTag))")
    }

    static func scriptURL(forBundleIdentifier bundleIdentifier: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("relaunch.sh")
    }

    /// Written by the host if its termination is cancelled after the script was spawned.
    /// The script polls for this and exits without touching anything.
    static func abortURL(forBundleIdentifier bundleIdentifier: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("install-aborted")
    }

    static func logURL(forBundleIdentifier bundleIdentifier: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("relaunch.log")
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

    /// Signals a spawned-but-still-waiting script to stand down, for a host whose
    /// termination was cancelled after the script was already running.
    static func abortPendingInstall(bundleIdentifier: String) {
        let url = abortURL(forBundleIdentifier: bundleIdentifier)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    /// Writes the script and launches it under `/bin/sh`, fully detached: no inherited
    /// stdio and no wait, so it outlives this process. Returns as soon as it is running.
    static func spawn(_ plan: RelaunchPlan) throws {
        try RelaunchScript.write(to: plan.scriptURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = plan.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
