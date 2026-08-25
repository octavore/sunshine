import Foundation

/// Selects which release asset to download, applied after architecture filtering
/// (Apple Silicon / universal only — see `AssetMatcher.select`).
public enum AssetMatching: Sendable {
    /// Default: any `.zip` or `.dmg` asset, preferring one whose name contains
    /// `bundleName` (or the running app's `CFBundleName` if `nil`) when several match.
    case zipOrDmgContainingApp(bundleName: String? = nil)
    case regex(String)
    case custom(@Sendable (GitHubAsset) -> Bool)
}

public enum AssetMatcher {
    private static let architectureTokens = ["arm64", "applesilicon", "universal"]
    private static let excludedArchitectureTokens = ["x8664", "x64", "intel"]

    /// Strips separators so "x86_64", "x86-64", and "x8664" all normalize identically.
    private static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Filters to assets viable on Apple Silicon (arm64 or universal builds only), then
    /// applies `matching` to pick one. Returns `nil` (never guesses) if nothing qualifies.
    public static func select(from assets: [GitHubAsset], matching: AssetMatching, bundleName: String?) -> GitHubAsset? {
        let archCandidates = assets.filter { asset in
            let normalized = normalize(asset.name)
            if excludedArchitectureTokens.contains(where: normalized.contains) { return false }
            // If no architecture is named at all, accept it (single-architecture-per-repo releases are common).
            let namesAnyArch = architectureTokens.contains(where: normalized.contains) || excludedArchitectureTokens.contains(where: normalized.contains)
            if !namesAnyArch { return true }
            return architectureTokens.contains(where: normalized.contains)
        }
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
