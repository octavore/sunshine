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
      let listItemComponent = components.first {
        if case .listItem = $0.kind { return true } else { return false }
      }
      if let previousIdentity, identity != previousIdentity {
        result += AttributedString(listItemComponent != nil ? "\n" : "\n\n")
      }
      if let listItemComponent, identity != previousIdentity {
        result += AttributedString(marker(for: listItemComponent, in: components))
      }
      result += input[run.range]
      previousIdentity = identity
    }

    return result
  }

  /// List items carry no literal bullet or number; `PresentationIntent` only records the
  /// ordinal and list kind. Build the marker text ourselves, indenting for nested lists.
  private static func marker(
    for listItemComponent: PresentationIntent.IntentType,
    in components: [PresentationIntent.IntentType]
  ) -> String {
    guard case .listItem(let ordinal) = listItemComponent.kind else { return "" }
    let nestingDepth = components.filter {
      switch $0.kind {
      case .unorderedList, .orderedList: return true
      default: return false
      }
    }.count
    let indent = String(repeating: "  ", count: max(0, nestingDepth - 1))
    let isOrdered = components.contains {
      if case .orderedList = $0.kind { return true } else { return false }
    }
    return isOrdered ? "\(indent)\(ordinal). " : "\(indent)• "
  }
}
