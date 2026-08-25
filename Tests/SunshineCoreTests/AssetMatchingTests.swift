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

    @Test func dmgIsAccepted() {
        let assets = [asset("MyApp-1.0.0-universal.dmg")]
        let match = AssetMatcher.select(from: assets, matching: .zipOrDmgContainingApp(), bundleName: nil)
        #expect(match?.name == "MyApp-1.0.0-universal.dmg")
    }
}
