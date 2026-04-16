import Foundation

/// Interface to the Coder deployment's Chats API.
///
/// Concrete implementations handle HTTP transport, SSE parsing,
/// and authentication. The service layer depends only on this
/// protocol so it can be tested with fakes.
public protocol CoderClient: Sendable {
    /// Create a new chat in the given organization.
    func createChat(
        organizationID: UUID,
        request: CreateChatRequest
    ) async throws -> Chat

    /// Send a user message and open an SSE stream for the response.
    func streamChat(
        chatID: UUID,
        message: String
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>

    /// Submit tool execution results and resume the SSE stream.
    func submitToolResults(
        chatID: UUID,
        results: [ToolResult]
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>

    /// Archive (soft-delete) a chat session.
    func archiveChat(chatID: UUID) async throws

    /// List available model configurations.
    func listModels(organizationID: UUID) async throws -> [ChatModel]
}
