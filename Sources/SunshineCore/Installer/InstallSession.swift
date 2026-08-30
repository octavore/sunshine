import Foundation

public struct VerifiedUpdate: Sendable {
    public let update: Update
    public let extractedAppURL: URL
    public let tempDirectory: URL
    public let verificationReport: VerificationReport
}

/// Runs the quit/swap/relaunch/rollback sequence while the current app is still alive.
/// The new bundle is moved into place and launched before the old process exits, so a
/// failure at any point can roll back to the still-running old bundle.
struct InstallSession: Sendable {
    let bundleIdentifier: String
    let verifier: UpdateVerifier
    /// Injectable so tests can simulate relaunch success/failure without actually
    /// launching a process via NSWorkspace.
    var relaunch: @Sendable (URL, String, String) async -> Bool = { installURL, bundleIdentifier, releaseTag in
        await RelaunchCoordinator.relaunchAndAwaitConfirmation(
            installURL: installURL,
            bundleIdentifier: bundleIdentifier,
            releaseTag: releaseTag
        )
    }

    /// Performs the swap and relaunch. On success this does not return meaningfully to
    /// the caller (the old process is expected to terminate); on failure the old bundle
    /// is restored and the error is thrown with the old app left fully intact.
    func install(_ verified: VerifiedUpdate, installURL: URL) async throws {
        guard InstallLocationChecker.isWritable(installURL) else {
            throw SunshineError.installLocationNotWritable(installURL)
        }

        // Re-verify immediately before commit: guards against a long delay between
        // "ready to install" and the user actually confirming.
        _ = try verifier.verify(appAt: verified.extractedAppURL)

        let oldAsidePath = installURL.deletingLastPathComponent()
            .appendingPathComponent(".\(installURL.deletingPathExtension().lastPathComponent) (old, \(Int(Date().timeIntervalSince1970))).app")

        let marker = PendingInstallMarker(
            installURL: installURL,
            oldAsidePath: oldAsidePath,
            newBundlePath: verified.extractedAppURL,
            releaseTag: verified.update.id,
            startedAt: Date()
        )
        try? marker.write(to: PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier))

        let fileManager = FileManager.default

        do {
            try fileManager.moveItem(at: installURL, to: oldAsidePath)
        } catch {
            throw SunshineError.installLocationNotWritable(installURL)
        }

        QuarantineRemover.removeQuarantine(at: verified.extractedAppURL)

        do {
            try fileManager.moveItem(at: verified.extractedAppURL, to: installURL)
        } catch {
            // Commit failed — restore the old bundle so the running app is unaffected.
            try? fileManager.moveItem(at: oldAsidePath, to: installURL)
            throw SunshineError.rollbackFailed(underlying: error)
        }

        let confirmed = await relaunch(installURL, bundleIdentifier, verified.update.id)

        guard confirmed else {
            // Roll back: remove the broken new bundle, restore the old one, do NOT
            // terminate the current (still-running, still-good) process.
            try? fileManager.removeItem(at: installURL)
            try? fileManager.moveItem(at: oldAsidePath, to: installURL)
            PendingInstallMarker.remove(at: PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier))
            throw SunshineError.relaunchFailed(underlying: CocoaError(.fileWriteUnknown))
        }

        try? fileManager.removeItem(at: oldAsidePath)
        PendingInstallMarker.remove(at: PendingInstallMarker.markerURL(forBundleIdentifier: bundleIdentifier))
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
