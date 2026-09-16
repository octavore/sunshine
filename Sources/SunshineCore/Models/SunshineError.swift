import Foundation

public enum SunshineError: Error, Sendable {
  case network(underlying: any Error)
  case invalidRepository(owner: String, repo: String)
  case rateLimited(resetAt: Date?)
  case noMatchingAsset
  case versionParseFailure(String)
  case downloadFailed(underlying: any Error)
  case extractionFailed(underlying: any Error)
  case verificationFailed(VerificationFailure)
  case installLocationNotWritable(URL)
  case sandboxedAppUnsupported
  case relaunchFailed(underlying: any Error)
  case rollbackFailed(underlying: any Error)
  case cancelled
}

extension SunshineError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .network(let underlying):
      return "Network error: \(underlying.localizedDescription)"
    case .invalidRepository(let owner, let repo):
      return "Could not build a GitHub API URL for repository \"\(owner)/\(repo)\"."
    case .rateLimited(let resetAt):
      if let resetAt {
        return "GitHub API rate limit exceeded. Try again after \(resetAt)."
      }
      return "GitHub API rate limit exceeded."
    case .noMatchingAsset:
      return "No release asset matched this Mac's architecture and the configured asset pattern."
    case .versionParseFailure(let string):
      return "Could not parse version string: \(string)"
    case .downloadFailed(let underlying):
      return "Download failed: \(underlying.localizedDescription)"
    case .extractionFailed(let underlying):
      return "Failed to extract the downloaded update: \(underlying.localizedDescription)"
    case .verificationFailed(let failure):
      return "Update could not be verified: \(failure)"
    case .installLocationNotWritable(let url):
      return "Cannot update automatically: \(url.path) is not writable by the current user."
    case .sandboxedAppUnsupported:
      return "Sunshine does not support self-updating sandboxed applications."
    case .relaunchFailed(let underlying):
      return "Failed to relaunch the updated app: \(underlying.localizedDescription)"
    case .rollbackFailed(let underlying):
      return
        "Update failed and could not be rolled back automatically: \(underlying.localizedDescription)"
    case .cancelled:
      return "Update cancelled."
    }
  }
}
