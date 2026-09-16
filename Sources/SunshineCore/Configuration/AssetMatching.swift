import Foundation

/// Selects which release asset to download, applied after architecture filtering
/// (assets that name an Intel architecture are excluded, see `AssetMatcher.select`).
public enum AssetMatching: Sendable {
    /// Default: any `.zip` or `.dmg` asset, preferring one whose name contains
    /// `bundleName` (or the running app's `CFBundleName` if `nil`) when several match.
    case zipOrDmgContainingApp(bundleName: String? = nil)
    case regex(String)
    case custom(@Sendable (GitHubAsset) -> Bool)
}

public enum AssetMatcher {
    /// Token sequences that mark an Intel-only build. "x86_64" and "x86-64" split into
    /// ["x86", "64"], so that pair is listed alongside the unseparated "x8664".
    private static let excludedArchitectureSequences: [[String]] = [["x86", "64"], ["x8664"], ["x64"], ["intel"]]

    /// Splits a filename into lowercase alphanumeric tokens, so "MyApp-1.0-x86_64.zip"
    /// becomes ["myapp", "1", "0", "x86", "64", "zip"].
    private static func tokens(_ name: String) -> [String] {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Matches whole tokens only, so "IntelliNote.zip" does not match "intel".
    private static func namesExcludedArchitecture(_ name: String) -> Bool {
        let parts = tokens(name)
        return excludedArchitectureSequences.contains { sequence in
            guard parts.count >= sequence.count else { return false }
            return (0...(parts.count - sequence.count)).contains { start in
                Array(parts[start..<(start + sequence.count)]) == sequence
            }
        }
    }

    /// Excludes assets that name an Intel architecture, then applies `matching` to pick
    /// one. Assets that name no architecture are kept, because single-architecture
    /// releases often omit it. Returns `nil` if nothing qualifies.
    public static func select(from assets: [GitHubAsset], matching: AssetMatching, bundleName: String?) -> GitHubAsset? {
        let archCandidates = assets.filter { !namesExcludedArchitecture($0.name) }
        guard !archCandidates.isEmpty else { return nil }

        switch matching {
        case .zipOrDmgContainingApp(let name):
            let formatCandidates = archCandidates.filter {
                $0.name.lowercased().hasSuffix(".zip") || $0.name.lowercased().hasSuffix(".dmg")
            }
            guard !formatCandidates.isEmpty else { return nil }
            let preferredName = (name ?? bundleName)?.lowercased()
            if let preferredName, let match = formatCandidates.first(where: { $0.name.lowercased().contains(preferredName) }) {
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
