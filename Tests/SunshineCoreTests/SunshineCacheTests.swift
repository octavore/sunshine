import Foundation
import Testing
@testable import SunshineCore

@Suite struct SunshineCacheTests {
    @Test func ordinaryTagsAndAssetNamesPassThroughUnchanged() {
        #expect(SunshineCache.safeComponent("v1.4.2") == "v1.4.2")
        #expect(SunshineCache.safeComponent("1.2.0-beta.1") == "1.2.0-beta.1")
        #expect(SunshineCache.safeComponent("MyApp-1.4.2-arm64.zip") == "MyApp-1.4.2-arm64.zip")
    }

    @Test func separatorsCannotEscapeTheCacheDirectory() {
        // Git allows "/" in a tag, which would otherwise nest a directory.
        #expect(SunshineCache.safeComponent("release/1.0") == "release_1.0")
        #expect(!SunshineCache.safeComponent("../../etc/passwd").contains("/"))
        #expect(!SunshineCache.safeComponent("..\\..\\windows").contains("\\"))
    }

    @Test func componentsOfOnlyDotsAreReplaced() {
        #expect(SunshineCache.safeComponent(".") == "_")
        #expect(SunshineCache.safeComponent("..") == "_")
        #expect(SunshineCache.safeComponent("") == "_")
    }

    @Test func assetExtensionsSurviveSanitizing() {
        // ArchiveExtractor dispatches on the extension, so it has to be preserved.
        #expect(SunshineCache.safeComponent("My App (arm64).zip").hasSuffix(".zip"))
        #expect(SunshineCache.safeComponent("My App (arm64).dmg").hasSuffix(".dmg"))
    }

    @Test func longNamesAreTruncated() {
        let component = SunshineCache.safeComponent(String(repeating: "a", count: 500))
        #expect(component.count == 120)
    }

    @Test func theUpdateDirectoryAndSentinelAgreeOnTheSanitizedTag() {
        let directory = SunshineCache.updateDirectory(forBundleIdentifier: "test.app", releaseTag: "release/1.0")
        #expect(directory.lastPathComponent == "release_1.0")

        // The script and the relaunched app both derive the sentinel from the raw tag, so
        // the two paths have to match exactly.
        let fromScript = RelaunchCoordinator.sentinelURL(forBundleIdentifier: "test.app", releaseTag: "release/1.0")
        let fromApp = RelaunchCoordinator.sentinelURL(forBundleIdentifier: "test.app", releaseTag: "release/1.0")
        #expect(fromScript == fromApp)
        #expect(fromScript.lastPathComponent == "launched-ok-release_1.0")
        #expect(fromScript.deletingLastPathComponent().lastPathComponent == "Sunshine")
    }
}
