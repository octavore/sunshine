import SunshineCore
import SwiftUI

public struct UpdateErrorView: View {
  let message: String
  let releaseURL: URL?
  let onDismiss: (() -> Void)?

  @Environment(\.dismiss) private var dismiss

  /// - Parameter onDismiss: Called after the view dismisses itself.
  public init(message: String, releaseURL: URL? = nil, onDismiss: (() -> Void)? = nil) {
    self.message = message
    self.releaseURL = releaseURL
    self.onDismiss = onDismiss
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Update Failed", systemImage: "exclamationmark.triangle")
        .font(.headline)
      Text(message)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        if let releaseURL {
          Link("Download the update manually", destination: releaseURL)
        }
        Spacer()
        Button("Dismiss") {
          dismiss()
          onDismiss?()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .frame(width: 380)
  }
}

#Preview {
  UpdateErrorView(
    message: "The GitHub API rate limit was exceeded. Try again after 5:00 PM.",
    releaseURL: URL(string: "https://github.com/example/example/releases/latest")
  )
}
