import Foundation

public enum UpdateState: Sendable, Equatable {
  case idle
  case checking
  case updateAvailable(Update)
  case downloading(Update, fractionComplete: Double)
  case verifying(Update)
  case readyToInstall(Update)
  case installing
  case upToDate
  case error(SunshineError)

  public static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.checking, .checking), (.installing, .installing), (.upToDate, .upToDate):
      return true
    case (.updateAvailable(let l), .updateAvailable(let r)): return l == r
    case (.downloading(let l, let lf), .downloading(let r, let rf)): return l == r && lf == rf
    case (.verifying(let l), .verifying(let r)): return l == r
    case (.readyToInstall(let l), .readyToInstall(let r)): return l == r
    case (.error(let l), .error(let r)): return "\(l)" == "\(r)"
    default: return false
    }
  }
}

public struct DownloadedUpdate: Sendable {
  public let update: Update
  public let archiveURL: URL
  public let tempDirectory: URL
}
