import SunshineCore
import SwiftUI

public struct UpdateErrorView: View {
  let message: String
  let releaseURL: URL?

  @Environment(\.dismiss) private var dismiss

  public init(message: String, releaseURL: URL? = nil) {
    self.message = message
    self.releaseURL = releaseURL
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
        Button("Dismiss") { dismiss() }
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
