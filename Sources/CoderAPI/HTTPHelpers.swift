import Foundation

// MARK: - JSON Codec

extension HTTPCoderClient {

    /// Shared JSON encoder. Uses snake_case key strategy so Swift
    /// camelCase property names encode to the wire format the Coder
    /// API expects (e.g. `modelConfigID` → `model_config_id`).
    ///
    /// Explicit `CodingKeys` on a type always win over the strategy,
    /// so types that already define their own keys are unaffected.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Shared JSON decoder. Uses snake_case → camelCase strategy and
    /// ISO 8601 date parsing for `created_at` / `updated_at` fields.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Decode `data` into `T`, wrapping any `DecodingError` as
    /// ``CoderAPIError/decodingError(underlying:)``.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw CoderAPIError.decodingError(underlying: error)
        }
    }
}

// MARK: - Auth

extension HTTPCoderClient {

    /// Apply the correct authentication header for the stored
    /// credential type:
    ///
    /// - Session token → `Coder-Session-Token: <token>`
    /// - OAuth access token → `Authorization: Bearer <token>`
    func applyAuth(to request: inout URLRequest) {
        switch auth {
        case .sessionToken(let token):
            request.setValue(token, forHTTPHeaderField: "Coder-Session-Token")
        case .accessToken(let token):
            request.setValue(
                "Bearer \(token)", forHTTPHeaderField: "Authorization"
            )
        }
    }
}

// MARK: - Request Building

extension HTTPCoderClient {

    /// Build an authorized `URLRequest` with a JSON-encoded body.
    func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw CoderAPIError.networkError(underlying: error)
        }
        applyAuth(to: &request)
        return request
    }

    /// Build an authorized `URLRequest` with no body (GET, DELETE).
    func makeRequest(path: String, method: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuth(to: &request)
        return request
    }
}

// MARK: - Execution & Error Mapping

extension HTTPCoderClient {

    /// Execute `request`, validate the HTTP status code, and return
    /// the response body as `Data`.
    ///
    /// Transport errors are wrapped as
    /// ``CoderAPIError/networkError(underlying:)``. Non-2xx responses
    /// are mapped to typed ``CoderAPIError`` cases via
    /// ``mapHTTPError(statusCode:data:)``.
    func execute(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
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

        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data)
        }

        return data
    }

    /// Map an HTTP error status code to a typed ``CoderAPIError``.
    ///
    /// For status codes that carry a server message, the response body
    /// is decoded as ``CoderErrorResponse``. If decoding fails the raw
    /// body string is used as the message.
    func mapHTTPError(statusCode: Int, data: Data) -> CoderAPIError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409:
            let message = serverMessage(from: data) ?? "Conflict"
            return .conflict(message: message)
        case 429: return .usageLimitExceeded
        default:
            let message = serverMessage(from: data)
                ?? HTTPURLResponse.localizedString(
                    forStatusCode: statusCode
                )
            return .serverError(statusCode: statusCode, message: message)
        }
    }

    /// Attempt to decode a `CoderErrorResponse` and return its
    /// `message` field, or fall back to the raw UTF-8 body.
    private func serverMessage(from data: Data) -> String? {
        if let response = try? JSONDecoder().decode(
            CoderErrorResponse.self, from: data
        ) {
            return response.message
        }
        return String(data: data, encoding: .utf8)
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
