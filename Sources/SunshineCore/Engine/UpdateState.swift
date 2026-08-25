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
        case let (.updateAvailable(l), .updateAvailable(r)): return l == r
        case let (.downloading(l, lf), .downloading(r, rf)): return l == r && lf == rf
        case let (.verifying(l), .verifying(r)): return l == r
        case let (.readyToInstall(l), .readyToInstall(r)): return l == r
        case let (.error(l), .error(r)): return "\(l)" == "\(r)"
        default: return false
        }
    }
}

public struct DownloadedUpdate: Sendable {
    public let update: Update
    public let archiveURL: URL
    public let tempDirectory: URL
}
