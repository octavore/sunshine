import Foundation

/// Selection of the release asset to download.
/// It applies after architecture filtering. Assets that name an Intel architecture are
/// excluded, see `AssetMatcher.select`.
public enum AssetMatching: Sendable {
  /// Default. Any `.zip` or `.dmg` asset.
  /// If several match, the asset whose name contains `bundleName` is preferred. If
  /// `bundleName` is `nil`, the running app's `CFBundleName` is used.
  case zipOrDmgContainingApp(bundleName: String? = nil)
  case regex(String)
  case custom(@Sendable (GitHubAsset) -> Bool)
}

public enum AssetMatcher {
  /// Token sequences that mark an Intel-only build.
  /// "x86_64" and "x86-64" split into ["x86", "64"]. That pair is listed with the
  /// unseparated "x8664".
  private static let excludedArchitectureSequences: [[String]] = [
    ["x86", "64"], ["x8664"], ["x64"], ["intel"],
  ]

  /// Split a filename into lowercase alphanumeric tokens.
  /// "MyApp-1.0-x86_64.zip" becomes ["myapp", "1", "0", "x86", "64", "zip"].
  private static func tokens(_ name: String) -> [String] {
    name.lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init)
  }

  /// Whether the name contains an excluded architecture.
  /// Only whole tokens match, so "IntelliNote.zip" does not match "intel".
  private static func namesExcludedArchitecture(_ name: String) -> Bool {
    let parts = tokens(name)
    return excludedArchitectureSequences.contains { sequence in
      guard parts.count >= sequence.count else { return false }
      return (0...(parts.count - sequence.count)).contains { start in
        Array(parts[start..<(start + sequence.count)]) == sequence
      }
    }
  }

  /// Exclude assets that name an Intel architecture, then apply `matching` to pick one.
  /// Assets without an architecture are kept, because single-architecture releases often
  /// omit it. Returns `nil` if no asset qualifies.
  public static func select(
    from assets: [GitHubAsset], matching: AssetMatching, bundleName: String?
  ) -> GitHubAsset? {
    let archCandidates = assets.filter { !namesExcludedArchitecture($0.name) }
    guard !archCandidates.isEmpty else { return nil }

    switch matching {
    case .zipOrDmgContainingApp(let name):
      let formatCandidates = archCandidates.filter {
        $0.name.lowercased().hasSuffix(".zip") || $0.name.lowercased().hasSuffix(".dmg")
      }
      guard !formatCandidates.isEmpty else { return nil }
      let preferredName = (name ?? bundleName)?.lowercased()
      if let preferredName,
        let match = formatCandidates.first(where: { $0.name.lowercased().contains(preferredName) })
      {
        return match
      }
      return formatCandidates.first
    case .regex(let pattern):
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      return archCandidates.first { asset in
        let range = NSRange(asset.name.startIndex..., in: asset.name)
        return regex.firstMatch(in: asset.name, range: range) != nil
      }
    case .custom(let predicate):
      return archCandidates.first(where: predicate)
    }
  }
}
