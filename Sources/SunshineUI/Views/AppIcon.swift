import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

extension Image {
  /// Icon of the running app, read from `Bundle.main` via `CFBundleIconFile` or
  /// `CFBundleIconName`.
  /// It is the default `appIcon` for `.sunshineUpdater(_:)`. Hosts get a logo without
  /// accessing `NSApplication`, which is main-actor isolated.
  public static func fromMainBundle() -> Image? {
    #if canImport(AppKit)
      let info = Bundle.main.infoDictionary
      let iconName =
        (info?["CFBundleIconFile"] as? String) ?? (info?["CFBundleIconName"] as? String)
      if let iconName, let nsImage = Bundle.main.image(forResource: iconName) {
        return Image(nsImage: nsImage)
      }
      return nil
    #else
      return nil
    #endif
  }
}
