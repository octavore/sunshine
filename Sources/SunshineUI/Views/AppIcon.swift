import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Image {
    /// The running app's own icon, read via `CFBundleIconFile`/`CFBundleIconName` from
    /// `Bundle.main`. Used as the default `appIcon` for `.sunshineUpdater(_:)` so hosts get
    /// a logo for free without touching `NSApplication` (which is main-actor isolated).
    public static func fromMainBundle() -> Image? {
        #if canImport(AppKit)
        let info = Bundle.main.infoDictionary
        let iconName = (info?["CFBundleIconFile"] as? String) ?? (info?["CFBundleIconName"] as? String)
        if let iconName, let nsImage = Bundle.main.image(forResource: iconName) {
            return Image(nsImage: nsImage)
        }
        return nil
        #else
        return nil
        #endif
    }
}
