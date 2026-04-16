import Foundation

// MARK: - Enums

/// The format to return individual messages in.
public enum MessageFormat: String, Sendable {
    case full
    case minimal
    case metadata
    case raw
}

// MARK: - Error

/// Errors returned by GmailClient operations.
public enum GmailAPIError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case httpError(statusCode: Int, data: Data)
    case decodingError(DecodingError)
    case unauthorized
    case notFound
    case rateLimited(retryAfter: String?)
    case serverError(statusCode: Int)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .httpError(let statusCode, _):
            return "HTTP error \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized — access token may be expired"
        case .notFound:
            return "Resource not found"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited — retry after \(retryAfter)s"
            }
            return "Rate limited"
        case .serverError(let statusCode):
            return "Server error \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Message List

public struct MessageListResponse: Decodable, Sendable {
    public let messages: [MessageRef]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
}

public struct MessageRef: Decodable, Sendable {
    public let id: String
    public let threadId: String
}

// MARK: - Thread List

public struct ThreadListResponse: Decodable, Sendable {
    public let threads: [ThreadRef]?
    public let nextPageToken: String?
}

public struct ThreadRef: Decodable, Sendable {
    public let id: String
    public let snippet: String?
    public let historyId: String?
}

// MARK: - Thread

public struct GmailThread: Decodable, Identifiable, Sendable {
    public let id: String
    public let historyId: String?
    public let messages: [GmailMessage]?
}

// MARK: - Message

public struct GmailMessage: Decodable, Identifiable, Sendable {
    public let id: String
    public let threadId: String
    public let labelIds: [String]?
    public let snippet: String?
    public let internalDate: String?
    public let payload: MessagePayload?
    public let sizeEstimate: Int?
    /// Only populated when format=raw.
    public let raw: String?
}

// MARK: - Message Payload (MIME tree)

public struct MessagePayload: Decodable, Sendable {
    public let partId: String?
    public let mimeType: String?
    public let filename: String?
    public let headers: [MessageHeader]?
    public let body: MessageBody?
    public let parts: [MessagePayload]?
}

public struct MessageHeader: Decodable, Sendable {
    public let name: String
    public let value: String
}

public struct MessageBody: Decodable, Sendable {
    public let attachmentId: String?
    public let size: Int?
    /// Base64url-encoded body data.
    public let data: String?
}

// MARK: - Labels

public struct GmailLabel: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: String?
    public let messageListVisibility: String?
    public let labelListVisibility: String?
    public let messagesTotal: Int?
    public let messagesUnread: Int?
}

/// Wrapper for the labels list endpoint response.
struct LabelsListResponse: Decodable {
    let labels: [GmailLabel]?
}

// MARK: - Profile

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String
    public let messagesTotal: Int?
    public let threadsTotal: Int?
    public let historyId: String?
}

// MARK: - Draft

public struct GmailDraft: Decodable, Sendable {
    public let id: String
    public let message: GmailMessage?
}

// MARK: - Modify Request

public struct ModifyRequest: Encodable, Sendable {
    public let addLabelIds: [String]?
    public let removeLabelIds: [String]?

    public init(addLabelIds: [String]?, removeLabelIds: [String]?) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
    }
}

// MARK: - Contact

public struct EmailContact: Sendable, Equatable {
    public let name: String?
    public let email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }
}
