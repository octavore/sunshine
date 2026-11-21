import Foundation

/// Comparable app version from `CFBundleShortVersionString` and `CFBundleVersion`.
/// `CFBundleVersion` breaks ties. Comparison follows semantic versioning precedence.
/// Dotted numeric components compare one by one, and missing trailing components count as
/// zero. The prerelease tail is compared next, then the build number.
public struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
  public let shortVersion: String
  public let buildVersion: String?

  public init(shortVersion: String, buildVersion: String? = nil) {
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
  }

  /// Parse a GitHub release tag such as "v1.4.2" or "1.4.2".
  public init(tag: String) {
    var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
      trimmed.removeFirst()
    }
    self.init(shortVersion: trimmed, buildVersion: nil)
  }

  public static func fromMainBundle() -> AppVersion {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "0"
    let build = info?["CFBundleVersion"] as? String
    return AppVersion(shortVersion: short, buildVersion: build)
  }

  /// Version split into numeric release components and semver prerelease identifiers.
  /// Build metadata after `+` is dropped. It does not affect precedence.
  private struct Parsed {
    let release: [Int]
    let prerelease: [String]
  }

  /// Whether the text is a non-empty run of ASCII digits.
  /// This is stricter than `Int(_:)`, which accepts signs and reads "+5" as 5.
  private static func isNumericIdentifier(_ text: Substring) -> Bool {
    !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
  }

  /// Parse "1.4.2", "1.4.2-beta.1", or "1.4.2-rc.1+build.7".
  /// Returns `nil` if any release component is not numeric. Unrecognized formats then
  /// offer no update.
  private static func parse(_ version: String) -> Parsed? {
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutBuild = trimmed.split(
      separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
    let split = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

    let releaseFields = split[0].split(separator: ".", omittingEmptySubsequences: false)
    guard !releaseFields.isEmpty else { return nil }
    var release: [Int] = []
    for field in releaseFields {
      guard isNumericIdentifier(field), let value = Int(field) else { return nil }
      release.append(value)
    }

    var prerelease: [String] = []
    if split.count > 1 {
      let identifiers = split[1].split(separator: ".", omittingEmptySubsequences: false)
      // "1.0.0-" and "1.0.0-a..b" are malformed. They are not versions without a prerelease.
      guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
      prerelease = identifiers.map(String.init)
    }

    return Parsed(release: release, prerelease: prerelease)
  }

  private static func compare(_ lhs: Parsed, _ rhs: Parsed) -> ComparisonResult {
    for index in 0..<max(lhs.release.count, rhs.release.count) {
      let l = index < lhs.release.count ? lhs.release[index] : 0
      let r = index < rhs.release.count ? rhs.release[index] : 0
      if l != r { return l < r ? .orderedAscending : .orderedDescending }
    }
    return comparePrerelease(lhs.prerelease, rhs.prerelease)
  }

  /// Semver prerelease precedence.
  /// A version with a prerelease tail ranks below the same version without one. Numeric
  /// identifiers compare numerically and rank below alphanumeric ones. A shorter run of
  /// otherwise equal identifiers ranks lower.
  private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
    if lhs.isEmpty && rhs.isEmpty { return .orderedSame }
    if lhs.isEmpty { return .orderedDescending }
    if rhs.isEmpty { return .orderedAscending }

    for index in 0..<max(lhs.count, rhs.count) {
      guard index < lhs.count else { return .orderedAscending }
      guard index < rhs.count else { return .orderedDescending }
      let l = lhs[index]
      let r = rhs[index]
      switch (isNumericIdentifier(l[...]), isNumericIdentifier(r[...])) {
      case (true, true):
        let li = Int(l) ?? 0
        let ri = Int(r) ?? 0
        if li != ri { return li < ri ? .orderedAscending : .orderedDescending }
      case (true, false):
        return .orderedAscending
      case (false, true):
        return .orderedDescending
      case (false, false):
        if l != r { return l < r ? .orderedAscending : .orderedDescending }
      }
    }
    return .orderedSame
  }

  public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    guard let l = parse(lhs.shortVersion), let r = parse(rhs.shortVersion) else {
      // An unparseable version never compares as greater. The result is "no update".
      return false
    }
    switch compare(l, r) {
    case .orderedAscending:
      return true
    case .orderedDescending:
      return false
    case .orderedSame:
      // Short versions are equal. The build number breaks the tie.
      switch (lhs.buildVersion, rhs.buildVersion) {
      case (let l?, let r?):
        if let li = Int(l), let ri = Int(r) { return li < ri }
        return l < r
      default:
        return false
      }
    }
  }

  /// Whether `candidate` is strictly newer than `self`.
  /// An equal or older version is never an update. This prevents downgrades.
  public func isUpdate(_ candidate: AppVersion) -> Bool {
    guard Self.parse(shortVersion) != nil, Self.parse(candidate.shortVersion) != nil else {
      return false
    }
    return self < candidate
  }

  public var description: String {
    if let buildVersion { return "\(shortVersion) (\(buildVersion))" }
    return shortVersion
  }
}
