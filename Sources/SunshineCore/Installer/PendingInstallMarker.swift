import Foundation

/// A breadcrumb written to disk immediately before an install swap begins, so a future
/// launch can detect (and, in later versions, recover from) a process that died mid-swap.
struct PendingInstallMarker: Codable {
    let installURL: URL
    let oldAsidePath: URL
    let newBundlePath: URL
    let releaseTag: String
    let startedAt: Date

    static func markerURL(forBundleIdentifier bundleIdentifier: String) -> URL {
        SunshineCache.directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("pending-install.plist")
    }

    func write(to url: URL) throws {
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> PendingInstallMarker? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(PendingInstallMarker.self, from: data)
    }

    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum SunshineCache {
    static func directory(forBundleIdentifier bundleIdentifier: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent("Sunshine", isDirectory: true)
    }

    static func updateDirectory(forBundleIdentifier bundleIdentifier: String, releaseTag: String) -> URL {
        directory(forBundleIdentifier: bundleIdentifier)
            .appendingPathComponent("updates", isDirectory: true)
            .appendingPathComponent(releaseTag, isDirectory: true)
    }
}
