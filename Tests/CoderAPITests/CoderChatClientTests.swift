import XCTest
@testable import CoderAPI

final class CoderClientTests: XCTestCase {
    func testClientInitialization() {
        let client = CoderClient(
            baseURL: URL(string: "https://coder.example.com")!,
            sessionToken: "test-token"
        )
        XCTAssertNotNil(client)
    }

    func testClientInitializationWithOAuth() {
        let client = CoderClient(
            baseURL: URL(string: "https://coder.example.com")!,
            accessToken: "oauth-token"
        )
        XCTAssertNotNil(client)
    }

    func testCoderAPIErrorDescriptions() {
        XCTAssertNotNil(CoderAPIError.unauthorized.errorDescription)
        XCTAssertNotNil(CoderAPIError.forbidden.errorDescription)
        XCTAssertNotNil(CoderAPIError.notFound.errorDescription)
        XCTAssertNotNil(
            CoderAPIError.conflict(message: "duplicate").errorDescription
        )
        XCTAssertNotNil(CoderAPIError.usageLimitExceeded.errorDescription)
        XCTAssertNotNil(
            CoderAPIError.serverError(
                statusCode: 500,
                message: "internal"
            ).errorDescription
        )
    }

    func testAnyCodableRoundTrip() throws {
        let original: AnyCodable = [
            "key": "value",
            "number": 42,
            "nested": ["a", "b"],
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testChatStatusDecoding() throws {
        let json = Data(#""requires_action""#.utf8)
        let status = try JSONDecoder().decode(ChatStatus.self, from: json)
        XCTAssertEqual(status, .requiresAction)
    }

    func testChatMessagePartTypeDecoding() throws {
        let json = Data(#""tool-call""#.utf8)
        let partType = try JSONDecoder().decode(
            ChatMessagePartType.self,
            from: json
        )
        XCTAssertEqual(partType, .toolCall)
    }

    func testChatInputPartTextFactory() {
        let part = ChatInputPart.text("hello")
        XCTAssertEqual(part.type, .text)
        XCTAssertEqual(part.text, "hello")
    }

    func testOAuthCodeVerifierLength() {
        let verifier = CoderOAuth.generateCodeVerifier()
        XCTAssertEqual(verifier.count, 128)
    }

    func testOAuthCodeChallengeIsDeterministic() {
        let verifier = "test-verifier-string"
        let c1 = CoderOAuth.generateCodeChallenge(verifier: verifier)
        let c2 = CoderOAuth.generateCodeChallenge(verifier: verifier)
        XCTAssertEqual(c1, c2)
        // S256 challenge must not contain padding characters.
        XCTAssertFalse(c1.contains("="))
    }

    func testOAuthAuthorizationURL() {
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
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], "my-client")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["state"], "random-state")
    }
}
