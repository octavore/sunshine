import Foundation

/// Text of the alerts shown by
/// ``SunshineUpdaterUIController/offerToMoveToApplicationsIfNeeded(allowsSuppression:confirmsReplacement:quitTimeout:text:)``.
/// Each property has a default. Change only the ones to customize.
public struct MoveToApplicationsText: Sendable {
  /// Title of the offer alert.
  public var offerTitle = "Move to Applications folder?"
  /// Body of the offer alert.
  public var offerMessage =
    "This app is running from a location where it cannot update itself. It can move itself to the Applications folder and relaunch."
  /// Default button of the offer alert.
  public var moveButton = "Move to Applications"
  /// Cancel button of the offer alert.
  public var dontMoveButton = "Don't Move"

  /// Title of the replacement alert. Receives the app name and the name of the folder.
  public var replaceTitle: @Sendable (_ appName: String, _ folderName: String) -> String = {
    "\($0) is already in the \($1) folder."
  }
  /// Body of the replacement alert.
  public var replaceMessage = "The existing copy is moved to the Trash."
  /// Default button of the replacement alert.
  public var replaceButton = "Replace"
  /// Cancel button of the replacement alert.
  public var cancelReplaceButton = "Cancel"

  /// Title of the alert shown if the move fails.
  public var failureTitle = "Could not move the app"

  public init() {}
}
