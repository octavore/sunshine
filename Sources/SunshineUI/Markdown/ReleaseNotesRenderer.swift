import Foundation

enum ReleaseNotesRenderer {
    static func render(_ markdown: String?) -> AttributedString {
        guard let markdown, !markdown.isEmpty else { return AttributedString("No release notes provided.") }
        return (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)))
            ?? AttributedString(markdown)
    }
}
