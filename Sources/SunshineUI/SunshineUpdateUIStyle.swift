/// How `.sunshineUpdater(_:)` presents an available update.
public enum SunshineUpdateUIStyle: Sendable, Equatable {
  /// The current default: a modal sheet appears as soon as an update is found.
  case sheet
  /// A small, dismissible badge appears in the window's bottom-trailing corner.
  /// Nothing interrupts the user; they open it when they're ready to review the update.
  /// See https://mitchellh.com/writing/non-trivial-vibing for the design this mirrors.
  case cornerIndicator
}
