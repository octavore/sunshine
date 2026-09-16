import Foundation

enum ReleaseNotesRenderer {
  /// Returns `nil` when there is nothing to render. Callers should hide the release-notes box
  /// in that case instead of showing an empty or placeholder state.
  static func render(_ markdown: String?) -> AttributedString? {
    guard let markdown, !markdown.isEmpty else { return nil }
    guard
      let parsed = try? AttributedString(
        markdown: markdown, options: .init(interpretedSyntax: .full))
    else {
      return AttributedString(markdown)
    }
    return insertingBlockBreaks(parsed)
  }

  /// `AttributedString(markdown:)` records block structure (headings, list items, paragraphs)
  /// as `PresentationIntent` attributes rather than literal newlines. A single SwiftUI `Text`
  /// only renders inline styling, so without this pass every block runs together on one line.
  private static func insertingBlockBreaks(_ input: AttributedString) -> AttributedString {
    var result = AttributedString()
    var previousIdentity: Int? = nil

    for run in input.runs {
      let components = run.presentationIntent?.components ?? []
      let identity = components.first?.identity
      if let previousIdentity, identity != previousIdentity {
        let isListItem = components.contains {
          if case .listItem = $0.kind { return true } else { return false }
        }
        result += AttributedString(isListItem ? "\n" : "\n\n")
      }
      result += input[run.range]
      previousIdentity = identity
    }

    return result
  }
}
