import SwiftUI

public struct CheckForUpdatesCommand: Commands {
  @ObservedObject var controller: SunshineUpdaterUIController

  public init(_ controller: SunshineUpdaterUIController) {
    self.controller = controller
  }

  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        controller.checkForUpdatesButtonTapped()
      }
    }
  }
}
