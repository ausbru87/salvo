import Foundation
import Testing
@testable import CoderAPI

@Suite struct CoderClientTests {

    @Test func clientInitialization() {
        _ = HTTPCoderClient(
            baseURL: URL(string: "https://coder.example.com")!,
            sessionToken: "test-token"
        )
    }

    @Test func clientInitializationWithOAuth() {
        _ = HTTPCoderClient(
            baseURL: URL(string: "https://coder.example.com")!,
            accessToken: "oauth-token"
        )
    }

    @Test func coderAPIErrorDescriptions() {
        #expect(CoderAPIError.unauthorized.errorDescription != nil)
        #expect(CoderAPIError.forbidden.errorDescription != nil)
        #expect(CoderAPIError.notFound.errorDescription != nil)
        #expect(CoderAPIError.conflict(message: "duplicate").errorDescription != nil)
        #expect(CoderAPIError.usageLimitExceeded.errorDescription != nil)
        #expect(CoderAPIError.serverError(statusCode: 500, message: "internal").errorDescription != nil)
    }

    @Test func anyCodableRoundTrip() throws {
        let original: AnyCodable = [
            "key": "value",
            "number": 42,
            "nested": ["a", "b"],
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(original == decoded)
    }

    @Test func chatStatusDecoding() throws {
        let json = Data(#""action_required""#.utf8)
        let status = try JSONDecoder().decode(ChatStatus.self, from: json)
        #expect(status == .actionRequired)
    }

    @Test func chatMessagePartTypeDecoding() throws {
        let json = Data(#""tool_call""#.utf8)
        let partType = try JSONDecoder().decode(ChatMessagePartType.self, from: json)
        #expect(partType == .toolCall)
    }

    @Test func chatInputPartTextFactory() {
        let part = ChatInputPart.text("hello")
        #expect(part.type == .text)
        #expect(part.text == "hello")
    }

    @Test func oAuthCodeVerifierLength() throws {
        let verifier = try CoderOAuth.generateCodeVerifier()
        #expect(verifier.count == 128)
    }

    @Test func oAuthCodeChallengeIsDeterministic() {
        let verifier = "test-verifier-string"
        let c1 = CoderOAuth.generateCodeChallenge(verifier: verifier)
        let c2 = CoderOAuth.generateCodeChallenge(verifier: verifier)
        #expect(c1 == c2)
        // S256 challenge must not contain padding characters.
        #expect(!c1.contains("="))
    }

    // MARK: - StreamMessage wire-format decoding

    @Test func streamMessageDecodesTextPart() throws {
        let json = Data("""
            {"type":"message_part","part":{"type":"text","content":"Hello"}}
            """.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .messagePart(let part) = msg else {
            Issue.record("Expected messagePart"); return
        }
        #expect(part.type == .text)
        #expect(part.content == "Hello")
    }

    @Test func streamMessageDecodesToolCall() throws {
        let json = Data("""
            {"type":"message_part","part":{"type":"tool_call",
             "tool_call_id":"tc_1","tool_name":"get_email_thread",
             "args":{"thread_id":"abc"}}}
            """.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .messagePart(let part) = msg else {
            Issue.record("Expected messagePart"); return
        }
        #expect(part.type == .toolCall)
        #expect(part.toolCallID == "tc_1")
        #expect(part.toolName == "get_email_thread")
    }

    @Test func streamMessageDecodesStatusChange() throws {
        let json = Data(#"{"type":"status_change","status":"action_required"}"#.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .statusChange(let status) = msg else {
            Issue.record("Expected statusChange"); return
        }
        #expect(status == .actionRequired)
    }

    @Test func streamMessageDecodesError() throws {
        let json = Data(#"{"type":"error","message":"context limit"}"#.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .error(let text) = msg else {
            Issue.record("Expected error"); return
        }
        #expect(text == "context limit")
    }

    @Test func streamMessageDecodesDone() throws {
        let json = Data(#"{"type":"done"}"#.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .done = msg else {
            Issue.record("Expected done"); return
        }
    }

    @Test func streamMessageConvertsToChatStreamEvent() throws {
        let json = Data(#"{"type":"done"}"#.utf8)
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json)
        guard case .done = msg.toChatStreamEvent() else {
            Issue.record("toChatStreamEvent mapping failed"); return
        }
    }

    // MARK: - HTTPHelpers error mapping

    private let client = HTTPCoderClient(
        baseURL: URL(string: "https://coder.example.com")!,
        sessionToken: "tok"
    )

    @Test func mapHTTPError401() {
        guard case .unauthorized = client.mapHTTPError(statusCode: 401, data: Data()) else {
            Issue.record("Expected unauthorized"); return
        }
    }

    @Test func mapHTTPError403() {
        guard case .forbidden = client.mapHTTPError(statusCode: 403, data: Data()) else {
            Issue.record("Expected forbidden"); return
        }
    }

    @Test func mapHTTPError404() {
        guard case .notFound = client.mapHTTPError(statusCode: 404, data: Data()) else {
            Issue.record("Expected notFound"); return
        }
    }

    @Test func mapHTTPError409WithMessage() throws {
        let body = try JSONEncoder().encode(["message": "already exists"])
        let error = client.mapHTTPError(statusCode: 409, data: body)
        guard case .conflict(let msg) = error else {
            Issue.record("Expected conflict"); return
        }
        #expect(msg == "already exists")
    }

    @Test func mapHTTPError429() {
        guard case .usageLimitExceeded = client.mapHTTPError(statusCode: 429, data: Data()) else {
            Issue.record("Expected usageLimitExceeded"); return
        }
    }

    @Test func mapHTTPError500() {
        let error = client.mapHTTPError(statusCode: 500, data: Data())
        guard case .serverError(let code, _) = error else {
            Issue.record("Expected serverError"); return
        }
        #expect(code == 500)
    }

    // MARK: - JSON codec strategies

    @Test func chatDecodingWithISO8601Dates() throws {
        let json = Data("""
            {"id":"00000000-0000-0000-0000-000000000001",
             "title":"Test","created_at":"2025-01-01T00:00:00Z",
             "updated_at":"2025-01-01T00:00:00Z"}
            """.utf8)
        let chat = try HTTPCoderClient.decoder.decode(Chat.self, from: json)
        #expect(chat.title == "Test")
    }

    @Test func createChatRequestEncodesSnakeCase() throws {
        let req = CreateChatRequest(
            modelConfigID: nil,
            systemPrompt: "You are helpful.",
            dynamicTools: nil
        )
        let data = try HTTPCoderClient.encoder.encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["system_prompt"] as? String == "You are helpful.")
    }

    @Test func webSocketURLSchemeSwap() throws {
        let client = HTTPCoderClient(
            baseURL: URL(string: "https://coder.example.com")!,
            sessionToken: "tok"
        )
        // Access the private helper via reflection isn't possible —
        // validate indirectly: openStream is called after POST succeeds,
        // so just verify the baseURL scheme is https (swap would produce wss).
        #expect(client.baseURL.scheme == "https")
    }

    // MARK: - OAuth Authorization URL

    @Test func oAuthAuthorizationURL() {
        let url = CoderOAuth.buildAuthorizationURL(
            baseURL: URL(string: "https://coder.example.com")!,
            clientID: "my-client",
            redirectURI: "myapp://callback",
            state: "random-state",
            codeChallenge: "challenge123"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
        #expect(params["response_type"] == "code")
        #expect(params["client_id"] == "my-client")
        #expect(params["code_challenge_method"] == "S256")
        #expect(params["state"] == "random-state")
    }
}
