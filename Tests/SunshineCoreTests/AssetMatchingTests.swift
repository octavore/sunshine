import Testing
import Foundation
@testable import SunshineCore

@Suite struct AssetMatchingTests {
    func asset(_ name: String) -> GitHubAsset {
        GitHubAsset(name: name, browserDownloadURL: URL(string: "https://example.com/\(name)")!, size: 100, contentType: nil)
    }

    @Test func selectsArm64Zip() {
        let assets = [asset("MyApp-1.0.0-x86_64.zip"), asset("MyApp-1.0.0-arm64.zip")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match?.name == "MyApp-1.0.0-arm64.zip")
    }

    @Test func selectsUniversalWhenNoArchNamed() {
        let assets = [asset("MyApp-1.0.0.zip")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match?.name == "MyApp-1.0.0.zip")
    }

    @Test func rejectsIntelOnlyAsset() {
        let assets = [asset("MyApp-1.0.0-x86_64.zip")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match == nil)
    }

    @Test func disambiguatesByBundleName() {
        let assets = [asset("Other-1.0.0-arm64.zip"), asset("MyApp-1.0.0-arm64.zip")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(bundleName: "MyApp"), bundleName: nil)
        #expect(match?.name == "MyApp-1.0.0-arm64.zip")
    }

    @Test func noMatchReturnsNil() {
        let assets = [asset("readme.txt")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match == nil)
    }

    /// Assets that name a supported architecture or no architecture are accepted, and
    /// assets that name an Intel architecture are rejected.
    @Test func namedAndUnnamedArchitecturesAreBothAccepted() {
        for name in ["MyApp-arm64.zip", "MyApp-universal.zip", "MyApp-apple-silicon.zip", "MyApp.zip"] {
            let match = AssetMatcher.select(from: [asset(name)], matching: .zipOrDmgContainingApp(), bundleName: nil)
            #expect(match?.name == name)
        }
        for name in ["MyApp-x86_64.zip", "MyApp-x86-64.zip", "MyApp_x8664.zip", "MyApp-x64.zip", "MyApp-intel.zip", "MyApp.Intel.dmg"] {
            let match = AssetMatcher.select(from: [asset(name)], matching: .zipOrDmgContainingApp(), bundleName: nil)
            #expect(match == nil)
        }
    }

    /// Excluded tokens match whole words, not substrings of the app name.
    @Test func excludedTokensInsideWordsAreIgnored() {
        for name in ["IntelliNote-1.0.zip", "Max64-1.0.zip", "Linux64Tools.zip"] {
            let match = AssetMatcher.select(from: [asset(name)], matching: .zipOrDmgContainingApp(), bundleName: nil)
            #expect(match?.name == name)
        }
    }

    @Test func dmgIsAccepted() {
        let assets = [asset("MyApp-1.0.0-universal.dmg")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match?.name == "MyApp-1.0.0-universal.dmg")
    }
}
