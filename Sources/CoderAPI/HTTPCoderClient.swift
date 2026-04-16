import Foundation

/// URLSession-backed implementation of ``CoderClient``.
///
/// Authenticates with either a Coder session token or an OAuth2
/// access token. All API calls are made against `baseURL`.
public struct HTTPCoderClient: CoderClient {

    private enum Auth: Sendable {
        case sessionToken(String)
        case accessToken(String)
    }

    private let baseURL: URL
    private let auth: Auth
    private let urlSession: URLSession

    // MARK: - Init

    public init(
        baseURL: URL,
        sessionToken: String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.auth = .sessionToken(sessionToken)
        self.urlSession = urlSession
    }

    public init(
        baseURL: URL,
        accessToken: String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.auth = .accessToken(accessToken)
        self.urlSession = urlSession
    }

    // MARK: - CoderClient

    public func createChat(
        organizationID: UUID,
        request: CreateChatRequest
    ) async throws -> Chat {
        // TODO: implement HTTP request
        throw CoderAPIError.notFound
    }

    public func streamChat(
        chatID: UUID,
        message: String
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // TODO: implement WebSocket streaming
        throw CoderAPIError.notFound
    }

    public func submitToolResults(
        chatID: UUID,
        results: [ToolResult]
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // TODO: implement
        throw CoderAPIError.notFound
    }

    public func archiveChat(chatID: UUID) async throws {
        // TODO: implement
    }

    public func listModels(
        organizationID: UUID
    ) async throws -> [ChatModel] {
        // TODO: implement
        throw CoderAPIError.notFound
    }
}
