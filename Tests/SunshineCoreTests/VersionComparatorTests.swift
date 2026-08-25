import Testing
@testable import SunshineCore

@Suite struct VersionComparatorTests {
    @Test func equalVersionsAreNotUpdates() {
        let a = AppVersion(shortVersion: "1.4.0")
        let b = AppVersion(shortVersion: "1.4.0")
        #expect(!a.isUpdate(b))
    }

    @Test func differingComponentCounts() {
        let a = AppVersion(shortVersion: "1.4")
        let b = AppVersion(shortVersion: "1.4.0")
        #expect(!a.isUpdate(b))
        #expect(!b.isUpdate(a))
    }

    @Test func newerPatchIsUpdate() {
        let a = AppVersion(shortVersion: "1.4.0")
        let b = AppVersion(shortVersion: "1.4.1")
        #expect(a.isUpdate(b))
        #expect(!b.isUpdate(a))
    }

    @Test func buildNumberTiebreak() {
        let a = AppVersion(shortVersion: "1.4.0", buildVersion: "100")
        let b = AppVersion(shortVersion: "1.4.0", buildVersion: "101")
        #expect(a.isUpdate(b))
    }

    @Test func malformedVersionsFailSafe() {
        let a = AppVersion(shortVersion: "not-a-version")
        let b = AppVersion(shortVersion: "1.0.0")
        #expect(!a.isUpdate(b))
    }

    @Test func tagPrefixIsStripped() {
        let tagVersion = AppVersion(tag: "v2.0.0")
        #expect(tagVersion.shortVersion == "2.0.0")
    }

    @Test func downgradeIsNeverAnUpdate() {
        let a = AppVersion(shortVersion: "2.0.0")
        let b = AppVersion(shortVersion: "1.0.0")
        #expect(!a.isUpdate(b))
    }
}
