import Foundation

/// A comparable app version derived from `CFBundleShortVersionString` (primary) and
/// `CFBundleVersion` (tiebreak). Comparisons are dotted-numeric, component-wise, with
/// missing trailing components treated as zero.
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

    private static func components(of version: String) -> [Int]? {
        let parts = version.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        for part in parts {
            // Take the leading numeric prefix of each component; non-numeric versions
            // (e.g. containing prerelease suffixes) fail to parse entirely.
            guard let value = Int(part) else { return nil }
            result.append(value)
        }
        return result
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        guard let l = components(of: lhs.shortVersion), let r = components(of: rhs.shortVersion) else {
            // Unparseable versions never compare as "greater" — fail safe to "no update".
            return false
        }
        let count = max(l.count, r.count)
        for index in 0..<count {
            let lv = index < l.count ? l[index] : 0
            let rv = index < r.count ? r[index] : 0
            if lv != rv { return lv < rv }
        }
        // Short versions equal — fall back to build number as a tiebreak.
        switch (lhs.buildVersion, rhs.buildVersion) {
        case let (l?, r?):
            if let li = Int(l), let ri = Int(r) { return li < ri }
            return l < r
        default:
            return false
        }
    }

    /// True only when `candidate` is strictly newer than `self` — never treats an equal
    /// or older version as an update, regardless of caller state (downgrade protection).
    public func isUpdate(_ candidate: AppVersion) -> Bool {
        guard Self.components(of: shortVersion) != nil, Self.components(of: candidate.shortVersion) != nil else {
            return false
        }
        return self < candidate
    }

    public var description: String {
        if let buildVersion { return "\(shortVersion) (\(buildVersion))" }
        return shortVersion
    }
}
