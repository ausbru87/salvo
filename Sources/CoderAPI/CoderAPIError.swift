import Foundation

/// Errors returned by the Coder API client.
public enum CoderAPIError: Error, LocalizedError, Sendable {
    /// HTTP 401 — session token or OAuth token is invalid or
    /// expired.
    case unauthorized

    /// HTTP 403 — the authenticated user lacks permission.
    case forbidden

    /// HTTP 404 — the requested resource does not exist.
    case notFound

    /// HTTP 409 — a conflicting operation was attempted.
    case conflict(message: String)

    /// HTTP 429 — usage limit exceeded.
    case usageLimitExceeded

    /// Any other non-2xx HTTP status code.
    case serverError(statusCode: Int, message: String)

    /// The response body could not be decoded into the expected
    /// type.
    case decodingError(underlying: Error)

    /// A transport-level error (DNS, TLS, timeout, etc.).
    case networkError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized: invalid or expired credentials."
        case .forbidden:
            return "Forbidden: insufficient permissions."
        case .notFound:
            return "Not found."
        case .conflict(let message):
            return "Conflict: \(message)"
        case .usageLimitExceeded:
            return "Usage limit exceeded."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let underlying):
            return "Decoding error: \(underlying.localizedDescription)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

/// A Coder API error response body. The server returns this
/// JSON structure for most error status codes.
struct CoderErrorResponse: Decodable {
    let message: String
    var detail: String?
}
