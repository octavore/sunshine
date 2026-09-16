import Foundation

public struct VerifiedUpdate: Sendable {
    public let update: Update
    public let extractedAppURL: URL
    public let tempDirectory: URL
    public let verificationReport: VerificationReport
}

/// Prepares the swap, then hands it to a detached shell script that waits for this
/// process to exit before touching anything. Nothing is moved while the host is alive, so
/// a host that fails to terminate leaves the installed bundle exactly as it was.
struct InstallSession: Sendable {
    let bundleIdentifier: String
    let verifier: UpdateVerifier
    /// Injectable so tests can inspect what would be spawned without running a process.
    var spawn: @Sendable (RelaunchPlan) throws -> Void = RelaunchCoordinator.spawn

    /// Validates, stages, and spawns the relaunch script. Returns once the script is
    /// running and waiting; the caller is then expected to terminate the process. A throw
    /// means nothing was moved and the installed app is untouched.
    func install(_ verified: VerifiedUpdate, installURL: URL) async throws {
        guard InstallLocationChecker.isWritable(installURL) else {
            throw SunshineError.installLocationNotWritable(installURL)
        }

        // Re-verify immediately before commit: guards against a long delay between
        // "ready to install" and the user actually confirming.
        _ = try verifier.verify(appAt: verified.extractedAppURL)

        let asideURL = installURL.deletingLastPathComponent()
            .appendingPathComponent(".\(installURL.deletingPathExtension().lastPathComponent) (old, \(Int(Date().timeIntervalSince1970))).app")

        // Done here rather than in the script: the staged bundle is already verified and
        // still ours, and it keeps `xattr` out of the shell.
        QuarantineRemover.removeQuarantine(at: verified.extractedAppURL)

        let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier)
        let marker = PendingInstallMarker(
            installURL: installURL,
            oldAsidePath: asideURL,
            newBundlePath: verified.extractedAppURL,
            releaseTag: verified.update.id,
            startedAt: Date()
        )
        // A write failure aborts the install. Without the marker, the next launch cannot
        // restore the bundle if the script dies mid-swap.
        try marker.write(to: markerURL)

        let sentinelURL = RelaunchCoordinator.sentinelURL(forBundleIdentifier: bundleIdentifier, releaseTag: verified.update.id)
        let abortURL = RelaunchCoordinator.abortURL(forBundleIdentifier: bundleIdentifier)
        // A same-tag reinstall could otherwise be confirmed by the previous install's
        // sentinel, and a previous cancelled install by its abort file.
        try? FileManager.default.removeItem(at: sentinelURL)
        try? FileManager.default.removeItem(at: abortURL)

        let plan = RelaunchPlan(
            scriptURL: RelaunchCoordinator.scriptURL(forBundleIdentifier: bundleIdentifier),
            hostProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            installURL: installURL,
            asideURL: asideURL,
            stagedURL: verified.extractedAppURL,
            sentinelURL: sentinelURL,
            markerURL: markerURL,
            abortURL: abortURL,
            logURL: RelaunchCoordinator.logURL(forBundleIdentifier: bundleIdentifier),
            releaseTag: verified.update.id
        )

        do {
            try spawn(plan)
        } catch {
            PendingInstallMarker.remove(at: markerURL)
            throw SunshineError.relaunchFailed(underlying: error)
        }
    }

    /// Finishes a swap whose script died partway through: if the installed bundle is gone
    /// but an aside copy from the recorded install is still present, move it back. Runs at
    /// `SunshineUpdater` init, before the stale-aside sweep.
    static func recoverInterruptedInstall(bundleIdentifier: String) {
        let markerURL = PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier)
        guard let marker = PendingInstallMarker.read(from: markerURL) else { return }

        let fileManager = FileManager.default
        let installed = fileManager.fileExists(atPath: marker.installURL.path)
        let aside = fileManager.fileExists(atPath: marker.oldAsidePath.path)

        if !installed && aside {
            try? fileManager.moveItem(at: marker.oldAsidePath, to: marker.installURL)
        } else if installed && aside {
            // The swap completed but cleanup did not; the aside copy is now dead weight.
            try? fileManager.removeItem(at: marker.oldAsidePath)
        }

        PendingInstallMarker.remove(at: markerURL)
    }

    /// Best-effort cleanup of aside'd bundles left behind by an interrupted install, run
    /// at each `SunshineUpdater` init so failed/aborted updates self-heal disk usage.
    static func sweepStaleAsideBundles(near installURL: URL, olderThan interval: TimeInterval = 24 * 60 * 60) {
        let parent = installURL.deletingLastPathComponent()
        let prefix = ".\(installURL.deletingPathExtension().lastPathComponent) (old, "
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-interval)
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
