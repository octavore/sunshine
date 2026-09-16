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

  public init(name: String, browserDownloadURL: URL, size: Int, contentType: String? = nil) {
    self.name = name
    self.browserDownloadURL = browserDownloadURL
    self.size = size
    self.contentType = contentType
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

  /// Builds a release directly, without decoding, for supplying a fixed list of releases
  /// explicitly (e.g. to `StaticReleasesProvider`, or in tests and SwiftUI previews).
  public init(
    tagName: String,
    name: String? = nil,
    body: String? = nil,
    draft: Bool = false,
    prerelease: Bool = false,
    publishedAt: Date? = nil,
    htmlURL: URL? = nil,
    assets: [GitHubAsset] = []
  ) {
    self.tagName = tagName
    self.name = name
    self.body = body
    self.draft = draft
    self.prerelease = prerelease
    self.publishedAt = publishedAt
    self.htmlURL = htmlURL
    self.assets = assets
  }
}
