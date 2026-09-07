import Foundation

/// A comparable app version derived from `CFBundleShortVersionString` (primary) and
/// `CFBundleVersion` (tiebreak). Comparisons follow semantic versioning precedence:
/// dotted-numeric components compared component-wise with missing trailing components
/// treated as zero, then the prerelease tail, then the build number.
public struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let shortVersion: String
    public let buildVersion: String?

    public init(shortVersion: String, buildVersion: String? = nil) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    /// Parses a GitHub release tag (e.g. "v1.4.2" or "1.4.2") into an `AppVersion`.
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

    /// A version split into its numeric release components and its semver prerelease
    /// identifiers. Build metadata (everything after `+`) is dropped: it takes no part in
    /// precedence.
    private struct Parsed {
        let release: [Int]
        let prerelease: [String]
    }

    /// True for a non-empty run of ASCII digits. Stricter than `Int(_:)`, which also
    /// accepts signs and would read "+5" as 5.
    private static func isNumericIdentifier(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Parses "1.4.2", "1.4.2-beta.1", or "1.4.2-rc.1+build.7". Returns `nil` for anything
    /// whose release components are not all numeric, so unrecognized formats fail safe.
    private static func parse(_ version: String) -> Parsed? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBuild = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
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
            // "1.0.0-" and "1.0.0-a..b" are malformed rather than prerelease-free.
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

    /// Semver prerelease precedence: a version carrying a prerelease tail ranks below the
    /// same version without one, numeric identifiers compare numerically and rank below
    /// alphanumeric ones, and a shorter run of otherwise-equal identifiers ranks lower.
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
            // Unparseable versions never compare as "greater" — fail safe to "no update".
            return false
        }
        switch compare(l, r) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            // Short versions equal — fall back to build number as a tiebreak.
            switch (lhs.buildVersion, rhs.buildVersion) {
            case let (l?, r?):
                if let li = Int(l), let ri = Int(r) { return li < ri }
                return l < r
            default:
                return false
            }
        }
    }

    /// True only when `candidate` is strictly newer than `self` — never treats an equal
    /// or older version as an update, regardless of caller state (downgrade protection).
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
