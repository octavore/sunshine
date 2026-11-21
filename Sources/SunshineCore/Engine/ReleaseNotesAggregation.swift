import Foundation

enum ReleaseNotesAggregation {
  /// Combined release notes body for `update`.
  /// The notes of `update` come first. Releases in `candidates` newer than `runningVersion`
  /// follow, ordered by version with the newest first. A patch to an older branch
  /// published later does not move up the list. Returns `nil` if there is nothing to
  /// combine.
  static func combinedNotes(
    for update: Update, candidates: [GitHubRelease], runningVersion: AppVersion
  ) -> String? {
    let intermediates =
      candidates
      .filter { runningVersion.isUpdate(AppVersion(tag: $0.tagName)) && $0.tagName != update.id }
      .sorted { AppVersion(tag: $0.tagName) > AppVersion(tag: $1.tagName) }

    var sections: [(tag: String, body: String)] = []
    if let body = update.releaseNotesMarkdown, !body.isEmpty {
      sections.append((update.id, body))
    }
    for release in intermediates {
      if let body = release.body, !body.isEmpty {
        sections.append((release.tagName, body))
      }
    }
    guard sections.count > 1 else { return nil }

    return
      sections
      .map { "## \($0.tag)\n\n\($0.body)" }
      .joined(separator: "\n\n---\n\n")
  }
}
