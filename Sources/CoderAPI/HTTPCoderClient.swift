import Foundation

/// URLSession-backed implementation of ``CoderClient``.
///
/// Authenticates with either a Coder session token or an OAuth2
/// access token. All HTTP calls target `baseURL` under the
/// `/api/experimental/chats` path prefix. Streaming responses are
/// delivered over a WebSocket (`wss://` or `ws://`) and wrapped in
/// `AsyncThrowingStream<ChatStreamEvent, Error>`.
public struct HTTPCoderClient: CoderClient {

    // MARK: - Stored auth credential

    enum Auth: Sendable {
        case sessionToken(String)
        case accessToken(String)
    }

    // MARK: - Stored properties

    let baseURL: URL
    let auth: Auth
    let urlSession: URLSession

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
        let body = CreateChatBody(
            organizationID: organizationID,
            modelConfigID: request.modelConfigID,
            systemPrompt: request.systemPrompt,
            dynamicTools: request.dynamicTools
        )
        let req = try makeRequest(
            path: "/api/experimental/chats",
            method: "POST",
            body: body
        )
        let data = try await execute(req)
        return try decode(Chat.self, from: data)
    }

    public func streamChat(
        chatID: UUID,
        message: String
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let req = try makeRequest(
            path: "/api/experimental/chats/\(chatID)/messages",
            method: "POST",
            body: SendMessageBody(content: message)
        )
        _ = try await execute(req)
        return try openStream(chatID: chatID)
    }

    public func submitToolResults(
        chatID: UUID,
        results: [ToolResult]
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let req = try makeRequest(
            path: "/api/experimental/chats/\(chatID)/tool-results",
            method: "POST",
            body: SubmitToolResultsBody(toolResults: results)
        )
        _ = try await execute(req)
        return try openStream(chatID: chatID)
    }

    public func archiveChat(chatID: UUID) async throws {
        let req = makeRequest(
            path: "/api/experimental/chats/\(chatID)",
            method: "DELETE"
        )
        _ = try await execute(req)
    }

    public func listModels(
        organizationID: UUID
    ) async throws -> [ChatModel] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "/api/experimental/chats/models"
            ),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [
            URLQueryItem(
                name: "organization_id",
                value: organizationID.uuidString
            )
        ]
        guard let url = components.url else {
            throw CoderAPIError.serverError(
                statusCode: 0, message: "Could not build models URL"
            )
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(to: &req)
        let data = try await execute(req)
        return try decode([ChatModel].self, from: data)
    }

    // MARK: - WebSocket streaming

    /// Build a WebSocket URL from `baseURL` by swapping the scheme
    /// (`https` → `wss`, `http` → `ws`).
    private func makeWebSocketURL(chatID: UUID) throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "/api/experimental/chats/\(chatID)/stream"
            ),
            resolvingAgainstBaseURL: true
        )!
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http":  components.scheme = "ws"
        default: break
        }
        guard let url = components.url else {
            throw CoderAPIError.serverError(
                statusCode: 0, message: "Could not build WebSocket URL"
            )
        }
        return url
    }

    /// Open a WebSocket to the chat stream endpoint and return an
    /// `AsyncThrowingStream` that yields ``ChatStreamEvent`` values
    /// decoded from each JSON frame.
    ///
    /// The stream terminates when the server sends a `done` or
    /// `error` frame, or when the WebSocket connection closes
    /// unexpectedly. Cancelling the `AsyncThrowingStream` closes the
    /// WebSocket with a `.goingAway` close code.
    private func openStream(
        chatID: UUID
    ) throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let wsURL = try makeWebSocketURL(chatID: chatID)
        var wsRequest = URLRequest(url: wsURL)
        applyAuth(to: &wsRequest)

        return AsyncThrowingStream { continuation in
            let task = urlSession.webSocketTask(with: wsRequest)
            task.resume()

            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }

            func receive() {
                task.receive { result in
                    switch result {
                    case .failure(let error):
                        continuation.finish(
                            throwing: CoderAPIError.networkError(
                                underlying: error
                            )
                        )

                    case .success(let message):
                        let text: String
                        switch message {
                        case .string(let s):
                            text = s
                        case .data(let d):
                            text = String(data: d, encoding: .utf8) ?? ""
                        @unknown default:
                            receive()
                            return
                        }

                        do {
                            let frame = try JSONDecoder().decode(
                                StreamMessage.self,
                                from: Data(text.utf8)
                            )
                            let event = frame.toChatStreamEvent()
                            continuation.yield(event)

                            switch event {
                            case .done:
                                task.cancel(
                                    with: .normalClosure, reason: nil
                                )
                                continuation.finish()
                            case .error(let msg):
                                task.cancel(
                                    with: .normalClosure, reason: nil
                                )
                                continuation.finish(
                                    throwing: CoderAPIError.serverError(
                                        statusCode: 0, message: msg
                                    )
                                )
                            default:
                                receive()
                            }
                        } catch {
                            continuation.finish(
                                throwing: CoderAPIError.decodingError(
                                    underlying: error
                                )
                            )
                        }
                    }
                }
            }

            receive()
        }
    }
}

// MARK: - Request Body Types

private struct CreateChatBody: Encodable {
    let organizationID: UUID
    let modelConfigID: UUID?
    let systemPrompt: String?
    let dynamicTools: [DynamicTool]?
}

private struct SendMessageBody: Encodable {
    let content: String
}

private struct SubmitToolResultsBody: Encodable {
    let toolResults: [ToolResult]
}
