import Foundation
import Testing
@testable import SunshineCore

@Suite struct ReleaseNotesAggregationTests {
    private func release(_ tag: String, body: String?, prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, body: body, prerelease: prerelease)
    }

    private func update(_ tag: String, body: String?) -> Update {
        Update(
            release: release(tag, body: body),
            asset: GitHubAsset(name: "App.zip", browserDownloadURL: URL(string: "https://example.com/App.zip")!, size: 1)
        )
    }

    @Test func combinesEveryReleaseNewerThanTheRunningVersion() throws {
        let combined = try #require(ReleaseNotesAggregation.combinedNotes(
            for: update("2.1.0", body: "Latest notes."),
            candidates: [
                release("2.1.0", body: "Latest notes."),
                release("2.0.0", body: "Middle notes."),
                release("1.9.0", body: "Older notes."),
                release("1.5.0", body: "Already installed."),
            ],
            runningVersion: AppVersion(shortVersion: "1.9.0")
        ))

        #expect(combined.contains("## 2.1.0"))
        #expect(combined.contains("## 2.0.0"))
        // 1.9.0 is the running version, not newer than it.
        #expect(!combined.contains("## 1.9.0"))
        #expect(!combined.contains("Already installed."))
    }

    @Test func theUpdatesOwnNotesLeadAndOrderIsByVersion() throws {
        let combined = try #require(ReleaseNotesAggregation.combinedNotes(
            for: update("2.1.0", body: "Newest."),
            candidates: [
                release("2.0.0", body: "Middle."),
                release("2.0.1", body: "Patch to the old branch, published last."),
            ],
            runningVersion: AppVersion(shortVersion: "1.0.0")
        ))

        let order = ["## 2.1.0", "## 2.0.1", "## 2.0.0"].map { combined.range(of: $0)?.lowerBound }
        #expect(order.allSatisfy { $0 != nil })
        #expect(order[0]! < order[1]!)
        #expect(order[1]! < order[2]!)
    }

    @Test func aSingleNewerReleaseIsNotAggregated() {
        #expect(ReleaseNotesAggregation.combinedNotes(
            for: update("2.0.0", body: "Only notes."),
            candidates: [release("2.0.0", body: "Only notes."), release("1.0.0", body: "Old.")],
            runningVersion: AppVersion(shortVersion: "1.0.0")
        ) == nil)
    }

    @Test func releasesWithoutNotesAreSkipped() throws {
        let combined = try #require(ReleaseNotesAggregation.combinedNotes(
            for: update("2.1.0", body: "Newest."),
            candidates: [release("2.0.0", body: nil), release("1.9.0", body: "Has notes.")],
            runningVersion: AppVersion(shortVersion: "1.0.0")
        ))

        #expect(!combined.contains("## 2.0.0"))
        #expect(combined.contains("## 1.9.0"))
    }

    @Test func anUpdateWithoutItsOwnNotesStillAggregatesTheRest() throws {
        let combined = try #require(ReleaseNotesAggregation.combinedNotes(
            for: update("2.1.0", body: nil),
            candidates: [release("2.0.0", body: "Middle."), release("1.9.5", body: "Older.")],
            runningVersion: AppVersion(shortVersion: "1.0.0")
        ))

        #expect(!combined.contains("## 2.1.0"))
        #expect(combined.contains("## 2.0.0"))
        #expect(combined.contains("## 1.9.5"))
    }

    @Test func candidatesWithUnparseableTagsAreIgnored() throws {
        let combined = try #require(ReleaseNotesAggregation.combinedNotes(
            for: update("2.1.0", body: "Newest."),
            candidates: [release("nightly", body: "Unversioned."), release("2.0.0", body: "Middle.")],
            runningVersion: AppVersion(shortVersion: "1.0.0")
        ))

        #expect(!combined.contains("Unversioned."))
        #expect(combined.contains("## 2.0.0"))
    }
}
