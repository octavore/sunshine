import Foundation

public struct RateLimitInfo: Sendable {
  public let remaining: Int?
  public let resetAt: Date?
}

/// Thin wrapper over the GitHub Releases REST API. No custom appcast format — the
/// release JSON itself (tag, body, assets) is the whole feed.
public struct GitHubReleasesClient: Sendable {
  public var session: URLSession
  public var token: String?

  public init(session: URLSession = .init(configuration: .ephemeral), token: String? = nil) {
    self.session = session
    self.token = token
  }

  private func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("Sunshine-Updater", forHTTPHeaderField: "User-Agent")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func rateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
    let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init)
    let resetEpoch = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
    let resetAt = resetEpoch.map { Date(timeIntervalSince1970: $0) }
    return RateLimitInfo(remaining: remaining, resetAt: resetAt)
  }

  private func perform(_ url: URL) async throws -> Data {
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request(url))
    } catch {
      throw SunshineError.network(underlying: error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw SunshineError.network(underlying: URLError(.badServerResponse))
    }
    let rateLimit = rateLimitInfo(from: http)
    if http.statusCode == 403, rateLimit.remaining == 0 {
      throw SunshineError.rateLimited(resetAt: rateLimit.resetAt)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw SunshineError.network(underlying: URLError(.badServerResponse))
    }
    return data
  }

  private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  /// Builds an API URL with `owner` and `repo` percent-encoded as single path segments,
  /// so a configuration containing a space, `#`, or `/` fails as an error rather than
  /// trapping on a nil URL or reaching an unintended endpoint.
  private func apiURL(
    owner: String, repo: String, endpoint: String, queryItems: [URLQueryItem] = []
  ) throws -> URL {
    let segmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    guard let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: segmentAllowed),
      let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: segmentAllowed),
      !encodedOwner.isEmpty, !encodedRepo.isEmpty
    else {
      throw SunshineError.invalidRepository(owner: owner, repo: repo)
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.percentEncodedPath = "/repos/\(encodedOwner)/\(encodedRepo)/\(endpoint)"
    components.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components.url else {
      throw SunshineError.invalidRepository(owner: owner, repo: repo)
    }
    return url
  }

  /// Fetches the single "latest" non-prerelease, non-draft release.
  public func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
    let url = try apiURL(owner: owner, repo: repo, endpoint: "releases/latest")
    let data = try await perform(url)
    return try decoder().decode(GitHubRelease.self, from: data)
  }

  /// Fetches recent releases (including prereleases/drafts as returned by the API),
  /// for callers that need to consider prereleases or aggregate notes across versions.
  public func fetchRecentReleases(owner: String, repo: String, perPage: Int = 10) async throws
    -> [GitHubRelease]
  {
    let url = try apiURL(
      owner: owner, repo: repo, endpoint: "releases",
      queryItems: [URLQueryItem(name: "per_page", value: String(perPage))]
    )
    let data = try await perform(url)
    return try decoder().decode([GitHubRelease].self, from: data)
  }
}
