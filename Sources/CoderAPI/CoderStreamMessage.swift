import Foundation

/// Internal wire representation of one JSON frame from the Coder
/// WebSocket stream.
///
/// The server sends newline-delimited JSON frames, each with a
/// required `type` discriminator field:
///
/// ```json
/// { "type": "message_part", "part": { "type": "text", "content": "Hi" } }
/// { "type": "status_change", "status": "action_required" }
/// { "type": "error", "message": "context limit exceeded" }
/// { "type": "done" }
/// ```
///
/// Only ``CoderAPI`` internals use this type. Callers of
/// ``CoderClient`` receive ``ChatStreamEvent`` values produced by
/// ``toChatStreamEvent()``. Isolating the wire format here means
/// field-name changes only require edits in this one file.
enum StreamMessage: Decodable {
    case messagePart(ChatMessagePart)
    case statusChange(ChatStatus)
    case error(String)
    case done

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case type, part, status, message
    }

    private enum MessageType: String, Decodable {
        case messagePart = "message_part"
        case statusChange = "status_change"
        case error
        case done
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(MessageType.self, forKey: .type)
        switch type_ {
        case .messagePart:
            let part = try container.decode(
                ChatMessagePart.self, forKey: .part
            )
            self = .messagePart(part)
        case .statusChange:
            let status = try container.decode(
                ChatStatus.self, forKey: .status
            )
            self = .statusChange(status)
        case .error:
            let message = try container.decode(
                String.self, forKey: .message
            )
            self = .error(message)
        case .done:
            self = .done
        }
    }

    // MARK: - Conversion

    /// Map the wire type to the public ``ChatStreamEvent``.
    func toChatStreamEvent() -> ChatStreamEvent {
        switch self {
        case .messagePart(let part): return .messagePart(part)
        case .statusChange(let status): return .statusChange(status)
        case .error(let msg): return .error(msg)
        case .done: return .done
        }
    }
}
