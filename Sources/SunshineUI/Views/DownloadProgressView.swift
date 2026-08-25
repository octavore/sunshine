import SwiftUI

public struct DownloadProgressView: View {
    let fractionComplete: Double
    let onCancel: (() -> Void)?

    public init(fractionComplete: Double, onCancel: (() -> Void)? = nil) {
        self.fractionComplete = fractionComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading update…")
            ProgressView(value: fractionComplete)
            if let onCancel {
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
