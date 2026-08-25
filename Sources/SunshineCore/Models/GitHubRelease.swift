import Foundation

public struct GitHubAsset: Sendable, Decodable, Equatable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

public struct GitHubRelease: Sendable, Decodable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let htmlURL: URL?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }
}
