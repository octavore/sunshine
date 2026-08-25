import Testing
import Foundation
@testable import SunshineCore

private struct PassingChecker: CodeSigningChecking {
    func validateSignature(at url: URL) throws -> String? { "TEAM123" }
    func teamIdentifierOfRunningApp() throws -> String? { "TEAM123" }
    func isNotarized(at url: URL) -> Bool { true }
}

@Suite struct InstallSessionTests {
    private func makeUpdate(tag: String = "v1.1.0") -> Update {
        let asset = GitHubAsset(name: "MyApp-1.1.0-arm64.zip", browserDownloadURL: URL(string: "https://example.com/a.zip")!, size: 1, contentType: nil)
        let release = GitHubRelease(tagName: tag, name: nil, body: "notes", draft: false, prerelease: false, publishedAt: nil, htmlURL: nil, assets: [asset])
        return Update(release: release, asset: asset)
    }

    /// Creates a fake "bundle" (just a directory with a .app extension and a marker
    /// file) — verification itself is mocked, so the bundle's contents don't need to be
    /// real code-signed binaries.
    private func makeFakeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SunshineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readMarker(at appURL: URL) -> String? {
        try? String(contentsOf: appURL.appendingPathComponent("marker.txt"), encoding: .utf8)
    }

    @Test func successfulSwapCleansUpOldBundleAndCommitsNew() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let installURL = installDir.appendingPathComponent("MyApp.app")
        try makeFakeApp(at: installURL, marker: "OLD")

        let extractedURL = root.appendingPathComponent("staging/MyApp.app")
        try makeFakeApp(at: extractedURL, marker: "NEW")

        let verifier = UpdateVerifier(requireNotarization: true, checker: PassingChecker())
        let verified = VerifiedUpdate(
            update: makeUpdate(), extractedAppURL: extractedURL, tempDirectory: root,
            verificationReport: VerificationReport(signatureValid: true, teamIdentifier: "TEAM123", runningAppTeamIdentifier: "TEAM123", teamIdentifierMatches: true, notarizationAccepted: true, details: "")
        )

        let session = InstallSession(bundleIdentifier: "com.test.app", verifier: verifier, relaunch: { _, _, _ in true })
        try await session.install(verified, installURL: installURL)

        #expect(readMarker(at: installURL) == "NEW")
        let siblings = try FileManager.default.contentsOfDirectory(at: installDir, includingPropertiesForKeys: nil)
        #expect(siblings.map(\.lastPathComponent) == ["MyApp.app"]) // aside'd old bundle was cleaned up
    }

    @Test func relaunchFailureRollsBackToOldBundle() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let installURL = installDir.appendingPathComponent("MyApp.app")
        try makeFakeApp(at: installURL, marker: "OLD")

        let extractedURL = root.appendingPathComponent("staging/MyApp.app")
        try makeFakeApp(at: extractedURL, marker: "NEW")

        let verifier = UpdateVerifier(requireNotarization: true, checker: PassingChecker())
        let verified = VerifiedUpdate(
            update: makeUpdate(), extractedAppURL: extractedURL, tempDirectory: root,
            verificationReport: VerificationReport(signatureValid: true, teamIdentifier: "TEAM123", runningAppTeamIdentifier: "TEAM123", teamIdentifierMatches: true, notarizationAccepted: true, details: "")
        )

        let session = InstallSession(bundleIdentifier: "com.test.app", verifier: verifier, relaunch: { _, _, _ in false })

        await #expect(throws: SunshineError.self) {
            try await session.install(verified, installURL: installURL)
        }

        // Old app must still be intact at the original path, and the broken new
        // bundle must not be left in place.
        #expect(readMarker(at: installURL) == "OLD")
        let siblings = try FileManager.default.contentsOfDirectory(at: installDir, includingPropertiesForKeys: nil)
        #expect(siblings.map(\.lastPathComponent) == ["MyApp.app"])
    }

    @Test func nonWritableInstallLocationIsRejectedWithoutTouchingFiles() async throws {
        let root = try makeTempRoot()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Applications").path)
            try? FileManager.default.removeItem(at: root)
        }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let installURL = installDir.appendingPathComponent("MyApp.app")
        try makeFakeApp(at: installURL, marker: "OLD")

        // Remove write permission on the parent directory so the swap's rename cannot
        // occur, matching a shared-machine /Applications scenario.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: installDir.path)

        let extractedURL = root.appendingPathComponent("staging/MyApp.app")
        try makeFakeApp(at: extractedURL, marker: "NEW")

        let verifier = UpdateVerifier(requireNotarization: true, checker: PassingChecker())
        let verified = VerifiedUpdate(
            update: makeUpdate(), extractedAppURL: extractedURL, tempDirectory: root,
            verificationReport: VerificationReport(signatureValid: true, teamIdentifier: "TEAM123", runningAppTeamIdentifier: "TEAM123", teamIdentifierMatches: true, notarizationAccepted: true, details: "")
        )

        let session = InstallSession(bundleIdentifier: "com.test.app", verifier: verifier, relaunch: { _, _, _ in true })

        await #expect(throws: SunshineError.self) {
            try await session.install(verified, installURL: installURL)
        }

        #expect(readMarker(at: installURL) == "OLD") // untouched
    }

    @Test func staleAsideBundlesAreSweptButRecentOnesAreKept() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let installDir = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let installURL = installDir.appendingPathComponent("MyApp.app")
        try makeFakeApp(at: installURL, marker: "CURRENT")

        let staleAside = installDir.appendingPathComponent(".MyApp (old, 1000000000).app")
        let recentAside = installDir.appendingPathComponent(".MyApp (old, 9999999999).app")
        try makeFakeApp(at: staleAside, marker: "STALE")
        try makeFakeApp(at: recentAside, marker: "RECENT")

        let oldDate = Date().addingTimeInterval(-48 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: staleAside.path)

        InstallSession.sweepStaleAsideBundles(near: installURL, olderThan: 24 * 60 * 60)

        #expect(!FileManager.default.fileExists(atPath: staleAside.path))
        #expect(FileManager.default.fileExists(atPath: recentAside.path))
    }
}
