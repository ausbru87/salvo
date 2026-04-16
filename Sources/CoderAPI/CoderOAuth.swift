import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// OAuth2 PKCE flow helper for Coder deployments.
///
/// Coder's OAuth2 provider endpoints:
/// - Authorization: `GET /oauth2/authorize`
/// - Token exchange: `POST /oauth2/tokens`
public enum CoderOAuth {

    // MARK: - PKCE Helpers

    /// Generates a cryptographically random code verifier (128
    /// characters, URL-safe base64 alphabet).
    ///
    /// - Throws: ``CoderOAuthError/randomGenerationFailed(_:)`` if
    ///   the system RNG returns a non-success status. Callers must
    ///   not proceed with a zero-filled verifier.
    public static func generateCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 96)
        let status = SecRandomCopyBytes(
            kSecRandomDefault, bytes.count, &bytes
        )
        guard status == errSecSuccess else {
            throw CoderOAuthError.randomGenerationFailed(status)
        }
        return Data(bytes)
            .base64URLEncoded()
            .prefix(128)
            .description
    }

    /// Derives the S256 code challenge from a code verifier.
    public static func generateCodeChallenge(
        verifier: String
    ) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Authorization URL

    /// Builds the authorization URL that should be opened in
    /// the user's browser.
    public static func buildAuthorizationURL(
        baseURL: URL,
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/oauth2/authorize"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    // MARK: - Token Exchange

    /// Exchanges an authorization code for an access token.
    public static func exchangeCodeForToken(
        baseURL: URL,
        clientID: String,
        code: String,
        codeVerifier: String,
        redirectURI: String,
        urlSession: URLSession = .shared
    ) async throws -> OAuthTokenResponse {
        let tokenURL = baseURL.appendingPathComponent("/oauth2/tokens")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = params.query?.data(using: .utf8)

        return try await performTokenRequest(
            request,
            urlSession: urlSession
        )
    }

    /// Refreshes an access token using a refresh token.
    public static func refreshToken(
        baseURL: URL,
        clientID: String,
        refreshToken: String,
        urlSession: URLSession = .shared
    ) async throws -> OAuthTokenResponse {
        let tokenURL = baseURL.appendingPathComponent("/oauth2/tokens")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        request.httpBody = params.query?.data(using: .utf8)

        return try await performTokenRequest(
            request,
            urlSession: urlSession
        )
    }

    // MARK: - Private

    private static func performTokenRequest(
        _ request: URLRequest,
        urlSession: URLSession
    ) async throws -> OAuthTokenResponse {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw CoderAPIError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CoderAPIError.networkError(
                underlying: URLError(.badServerResponse)
            )
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoderAPIError.serverError(
                statusCode: http.statusCode,
                message: body
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw CoderAPIError.decodingError(underlying: error)
        }
    }
}

// MARK: - OAuth Token Response

/// The token response from Coder's OAuth2 token endpoint.
public struct OAuthTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public var expiresIn: Int?
    public var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Errors

/// Errors thrown by ``CoderOAuth`` helpers.
public enum CoderOAuthError: Error, LocalizedError, Sendable {
    /// The system RNG returned a non-success status code. Using
    /// a zero-filled verifier would compromise PKCE security.
    case randomGenerationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "Failed to generate cryptographic random bytes (OSStatus \(status))."
        }
    }
}

// MARK: - Base64URL Encoding

extension Data {
    /// Returns a base64url-encoded string (no padding) per
    /// RFC 7636 appendix A.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
