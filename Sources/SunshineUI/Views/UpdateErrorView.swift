import SwiftUI
import SunshineCore

public struct UpdateErrorView: View {
    let message: String
    let releaseURL: URL?

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
            if let releaseURL {
                Link("Download the update manually", destination: releaseURL)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
