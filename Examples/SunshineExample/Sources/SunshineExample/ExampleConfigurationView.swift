import Sunshine
import SwiftUI

/// Lets you inspect and reset the `UserDefaults` state `SunshineUpdater` persists (skipped
/// version, remind-later date, preferences) and tweak the example app's simulated "latest
/// release". This is useful because those defaults otherwise silently survive between runs and can
/// make an update look "stuck" (e.g. `UpdateIndicatorView` never appearing again after you
/// once tap "Skip This Version").
struct ExampleConfigurationView: View {
  @ObservedObject var controller: SunshineUpdaterUIController
  let appliedReleaseConfig: ExampleReleaseConfig
  let onApply: (ExampleReleaseConfig) -> Void

  @State private var draft: ExampleReleaseConfig
  @State private var storedDefaults: [(key: String, value: String)] = []

  init(
    controller: SunshineUpdaterUIController, appliedReleaseConfig: ExampleReleaseConfig,
    onApply: @escaping (ExampleReleaseConfig) -> Void
  ) {
    self.controller = controller
    self.appliedReleaseConfig = appliedReleaseConfig
    self.onApply = onApply
    _draft = State(initialValue: appliedReleaseConfig)
  }

  private var keyPrefix: String { ExampleData.userDefaultsKeyPrefix }

  var body: some View {
    Form {
      Section("Example Release") {
        TextField("Latest Version", text: $draft.latestVersion)
        Toggle("Include Release Notes", isOn: $draft.includeReleaseNotes)
        Toggle("Prerelease", isOn: $draft.isPrerelease)
        Button("Apply & Check for Updates") { onApply(draft) }
          .disabled(draft == appliedReleaseConfig)
      }

      Section("Stored Defaults") {
        Text(keyPrefix)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        if storedDefaults.isEmpty {
          Text("No saved data.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(storedDefaults, id: \.key) { item in
            LabeledContent(item.key, value: item.value)
          }
        }
        Button("Reset Saved Data", role: .destructive, action: resetDefaults)
          .disabled(storedDefaults.isEmpty)
      }
    }
    .formStyle(.grouped)
    .onAppear(perform: refresh)
  }

  private func refresh() {
    let all = UserDefaults.standard.dictionaryRepresentation()
    storedDefaults =
      all
      .filter { $0.key.hasPrefix(keyPrefix) }
      .map { (key: String($0.key.dropFirst(keyPrefix.count)), value: "\($0.value)") }
      .sorted { $0.key < $1.key }
  }

  private func resetDefaults() {
    for item in storedDefaults {
      UserDefaults.standard.removeObject(forKey: keyPrefix + item.key)
    }
    refresh()
    controller.checkForUpdatesButtonTapped()
  }
}
