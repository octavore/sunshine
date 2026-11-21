/// How `.sunshineUpdater(_:)` presents an available update.
public enum SunshineUpdateUIStyle: Sendable, Equatable {
  /// Default style. A modal sheet appears as soon as an update is found.
  case sheet
  /// Small, dismissible badge in the bottom-trailing corner of the window.
  /// Nothing interrupts the user. They open the badge to review the update.
  /// The design follows https://mitchellh.com/writing/non-trivial-vibing.
  case cornerIndicator
}
