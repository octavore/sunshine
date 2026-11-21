import Foundation

enum ReleaseNotesRenderer {
  /// Render markdown release notes.
  /// Returns `nil` if there is nothing to render. Callers hide the release notes box then.
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

  /// Insert newlines between blocks.
  /// `AttributedString(markdown:)` records block structure (headings, list items,
  /// paragraphs) as `PresentationIntent` attributes and not as newlines. A SwiftUI `Text`
  /// renders only inline styling. Without this pass, all blocks appear on one line.
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

  /// Marker text for a list item.
  /// List items have no bullet or number. `PresentationIntent` records only the ordinal and
  /// list kind. Nested lists are indented.
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
