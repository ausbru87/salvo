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
