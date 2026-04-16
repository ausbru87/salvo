import Foundation

// MARK: - Token Store

/// Actor that serializes reads and writes to the mutable OAuth access
/// token. The `HTTPGmailClient` struct holds a reference to this
/// actor, making the struct `Sendable` while keeping token refresh
/// mutation safe under Swift Concurrency.
private actor GmailTokenStore {
    var accessToken: String
    let refreshToken: String
    let clientID: String

    init(accessToken: String, refreshToken: String, clientID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.clientID = clientID
    }

    func updateAccessToken(_ token: String) {
        accessToken = token
    }
}

// MARK: - HTTPGmailClient

/// URLSession-backed implementation of ``GmailClient``.
///
/// All requests target `https://gmail.googleapis.com/gmail/v1/users/me/`
/// with an `Authorization: Bearer <accessToken>` header. On a 401
/// response the client attempts one token refresh via
/// ``GmailOAuth/refreshAccessToken(clientID:refreshToken:)`` and
/// retries; subsequent 401s throw ``GmailAPIError/unauthorized``.
public struct HTTPGmailClient: GmailClient {

    private static let baseURL = URL(
        string: "https://gmail.googleapis.com/gmail/v1/users/me"
    )!

    private let urlSession: URLSession
    private let tokenStore: GmailTokenStore

    // MARK: - Init

    public init(
        accessToken: String,
        refreshToken: String,
        clientID: String,
        urlSession: URLSession = .shared
    ) {
        self.tokenStore = GmailTokenStore(
            accessToken: accessToken,
            refreshToken: refreshToken,
            clientID: clientID
        )
        self.urlSession = urlSession
    }

    // MARK: - GmailClient

    public func getProfile() async throws -> GmailProfile {
        let req = try await makeRequest(path: "/profile")
        let data = try await execute(req)
        return try decode(GmailProfile.self, from: data)
    }

    public func listMessages(
        query: String?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> MessageListResponse {
        var items: [URLQueryItem] = []
        if let q = query        { items.append(.init(name: "q", value: q)) }
        if let n = maxResults   { items.append(.init(name: "maxResults", value: "\(n)")) }
        if let p = pageToken    { items.append(.init(name: "pageToken", value: p)) }
        let req = try await makeRequest(path: "/messages", queryItems: items)
        let data = try await execute(req)
        return try decode(MessageListResponse.self, from: data)
    }

    public func getMessage(
        id: String,
        format: MessageFormat?
    ) async throws -> GmailMessage {
        var items: [URLQueryItem] = []
        if let f = format { items.append(.init(name: "format", value: f.rawValue)) }
        let req = try await makeRequest(
            path: "/messages/\(id)", queryItems: items
        )
        let data = try await execute(req)
        return try decode(GmailMessage.self, from: data)
    }

    public func getThread(
        id: String,
        format: MessageFormat?
    ) async throws -> GmailThread {
        var items: [URLQueryItem] = []
        if let f = format { items.append(.init(name: "format", value: f.rawValue)) }
        let req = try await makeRequest(
            path: "/threads/\(id)", queryItems: items
        )
        let data = try await execute(req)
        return try decode(GmailThread.self, from: data)
    }

    public func listLabels() async throws -> [GmailLabel] {
        let req = try await makeRequest(path: "/labels")
        let data = try await execute(req)
        let response = try decode(LabelsListResponse.self, from: data)
        return response.labels ?? []
    }

    // MARK: - Request Building

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: true
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw GmailAPIError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let token = await tokenStore.accessToken
        request.setValue(
            "Bearer \(token)", forHTTPHeaderField: "Authorization"
        )
        return request
    }

    // MARK: - Execution with Token Refresh

    /// Execute `request`. On a 401 response, refresh the access
    /// token and retry once before throwing ``GmailAPIError/unauthorized``.
    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode == 401 {
            return try await refreshAndRetry(request)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw mapError(statusCode: http.statusCode, data: data, response: http)
        }
        return data
    }

    private func performRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw GmailAPIError.networkError(error)
        }
    }

    /// Refresh the access token and retry the request once.
    private func refreshAndRetry(_ original: URLRequest) async throws -> Data {
        let refreshToken = tokenStore.refreshToken
        let clientID = tokenStore.clientID

        let tokenResponse = try await GmailOAuth.refreshAccessToken(
            clientID: clientID,
            refreshToken: refreshToken
        )
        await tokenStore.updateAccessToken(tokenResponse.accessToken)

        var retried = original
        retried.setValue(
            "Bearer \(tokenResponse.accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await performRequest(retried)
        guard let http = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GmailAPIError.unauthorized }
            throw mapError(statusCode: http.statusCode, data: data, response: http)
        }
        return data
    }

    // MARK: - Error Mapping

    private func mapError(
        statusCode: Int,
        data: Data,
        response: HTTPURLResponse
    ) -> GmailAPIError {
        switch statusCode {
        case 401: return .unauthorized
        case 404: return .notFound
        case 429:
            let retryAfter = response.value(
                forHTTPHeaderField: "Retry-After"
            )
            return .rateLimited(retryAfter: retryAfter)
        case 500...: return .serverError(statusCode: statusCode)
        default:    return .httpError(statusCode: statusCode, data: data)
        }
    }

    // MARK: - JSON Decode

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode<T: Decodable>(
        _ type: T.Type, from data: Data
    ) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw GmailAPIError.decodingError(error)
        }
    }
}
