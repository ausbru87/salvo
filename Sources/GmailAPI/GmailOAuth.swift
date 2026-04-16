import Foundation

/// Google OAuth2 constants and helpers for the Gmail API.
public enum GmailOAuth {
    // MARK: - Endpoints

    public static let authorizationEndpoint =
        "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenEndpoint =
        "https://oauth2.googleapis.com/token"

    // MARK: - Scopes

    public static let scopeReadonly =
        "https://www.googleapis.com/auth/gmail.readonly"
    public static let scopeSend =
        "https://www.googleapis.com/auth/gmail.send"
    public static let scopeModify =
        "https://www.googleapis.com/auth/gmail.modify"

    /// Convenience collection of all scopes needed for full
    /// read/write/send access.
    public static let allScopes = [scopeReadonly, scopeSend, scopeModify]

    // MARK: - Authorization URL

    /// Builds the Google OAuth2 authorization URL that the user
    /// should be directed to in a browser or ASWebAuthenticationSession.
    public static func buildAuthorizationURL(
        clientID: String,
        redirectURI: String,
        state: String,
        scopes: [String] = allScopes
    ) -> URL {
        var components = URLComponents(
            string: authorizationEndpoint
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        // The components are well-formed by construction, so force-
        // unwrap is safe.
        return components.url!
    }

    // MARK: - Token Exchange

    /// Exchanges an authorization code for access and refresh tokens.
    public static func exchangeCodeForToken(
        clientID: String,
        code: String,
        redirectURI: String
    ) async throws -> GoogleOAuthTokenResponse {
        let params = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        return try await tokenRequest(params: params)
    }

    /// Refreshes an expired access token using a refresh token.
    public static func refreshAccessToken(
        clientID: String,
        refreshToken: String
    ) async throws -> GoogleOAuthTokenResponse {
        let params = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        return try await tokenRequest(params: params)
    }

    // MARK: - Private

    /// Posts a form-encoded request to the Google token endpoint and
    /// decodes the response.
    private static func tokenRequest(
        params: [String: String]
    ) async throws -> GoogleOAuthTokenResponse {
        guard let url = URL(string: tokenEndpoint) else {
            throw GmailAPIError.invalidURL(tokenEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let body = params.map { key, value in
            let escapedKey = key.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? key
            let escapedValue = value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(
                for: request
            )
        } catch {
            throw GmailAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError(
                URLError(.badServerResponse)
            )
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw GmailAPIError.httpError(
                statusCode: httpResponse.statusCode,
                data: data
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(
                GoogleOAuthTokenResponse.self,
                from: data
            )
        } catch let error as DecodingError {
            throw GmailAPIError.decodingError(error)
        }
    }
}

// MARK: - Token Response

public struct GoogleOAuthTokenResponse: Decodable, Sendable {
    /// The short-lived access token.
    public let accessToken: String
    /// Typically "Bearer".
    public let tokenType: String
    /// Lifetime in seconds.
    public let expiresIn: Int
    /// Only present on the first authorization code exchange.
    public let refreshToken: String?
    /// Space-separated list of granted scopes.
    public let scope: String?
}
