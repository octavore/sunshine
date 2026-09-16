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

  @Test func prereleaseTagsParseAndCompare() {
    let beta = AppVersion(tag: "v1.2.0-beta.1")
    #expect(beta.shortVersion == "1.2.0-beta.1")
    #expect(AppVersion(shortVersion: "1.1.0").isUpdate(beta))
    #expect(beta.isUpdate(AppVersion(shortVersion: "1.2.0")))
  }

  @Test func prereleaseRanksBelowItsRelease() {
    let beta = AppVersion(shortVersion: "1.2.0-beta.1")
    let final = AppVersion(shortVersion: "1.2.0")
    #expect(beta.isUpdate(final))
    #expect(!final.isUpdate(beta))
  }

  @Test func prereleaseIdentifiersOrderBySemverRules() {
    // Numeric identifiers compare numerically, not lexically.
    #expect(
      AppVersion(shortVersion: "1.0.0-beta.2").isUpdate(AppVersion(shortVersion: "1.0.0-beta.10")))
    // Numeric identifiers rank below alphanumeric ones.
    #expect(AppVersion(shortVersion: "1.0.0-1").isUpdate(AppVersion(shortVersion: "1.0.0-alpha")))
    // A shorter run of otherwise-equal identifiers ranks lower.
    #expect(
      AppVersion(shortVersion: "1.0.0-beta").isUpdate(AppVersion(shortVersion: "1.0.0-beta.1")))
    // Alphanumeric identifiers compare lexically.
    #expect(
      AppVersion(shortVersion: "1.0.0-alpha").isUpdate(AppVersion(shortVersion: "1.0.0-beta")))
  }

  @Test func buildMetadataIsIgnoredForPrecedence() {
    let a = AppVersion(shortVersion: "1.0.0+build.1")
    let b = AppVersion(shortVersion: "1.0.0+build.9")
    #expect(!a.isUpdate(b))
    #expect(!b.isUpdate(a))
    #expect(a.isUpdate(AppVersion(shortVersion: "1.0.1")))
  }

  @Test func malformedPrereleaseTailsFailSafe() {
    for malformed in ["1.0.0-", "1.0.0-a..b", "1.0.x-beta", "v-beta"] {
      let candidate = AppVersion(shortVersion: malformed)
      #expect(!AppVersion(shortVersion: "1.0.0").isUpdate(candidate))
      #expect(!candidate.isUpdate(AppVersion(shortVersion: "9.0.0")))
    }
  }
}
