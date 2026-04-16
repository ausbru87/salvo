import Foundation

// MARK: - Chat

/// A single Coder Chat conversation.
public struct Chat: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Create Chat Request

/// Parameters for creating a new Coder Chat.
public struct CreateChatRequest: Encodable, Sendable {
    public let modelConfigID: UUID?
    public let systemPrompt: String?
    public let dynamicTools: [DynamicTool]?

    public init(
        modelConfigID: UUID?,
        systemPrompt: String?,
        dynamicTools: [DynamicTool]?
    ) {
        self.modelConfigID = modelConfigID
        self.systemPrompt = systemPrompt
        self.dynamicTools = dynamicTools
    }

    enum CodingKeys: String, CodingKey {
        case modelConfigID = "model_config_id"
        case systemPrompt = "system_prompt"
        case dynamicTools = "dynamic_tools"
    }
}

// MARK: - Dynamic Tool

/// A tool definition registered with a Coder Chat session so the
/// LLM can request local execution.
public struct DynamicTool: Codable, Sendable {
    public let name: String
    public let description: String
    public let schema: AnyCodable

    public init(name: String, description: String, schema: AnyCodable) {
        self.name = name
        self.description = description
        self.schema = schema
    }
}

// MARK: - Stream Events

/// A single server-sent event from a Coder Chat stream.
public enum ChatStreamEvent: Sendable {
    case messagePart(ChatMessagePart)
    case statusChange(ChatStatus)
    case error(String)
    case done
}

/// One chunk of a streamed chat message.
public struct ChatMessagePart: Codable, Sendable {
    public let type: ChatMessagePartType
    public let content: String?
    public let toolCallID: String?
    public let toolName: String?
    public let args: AnyCodable?

    public init(
        type: ChatMessagePartType,
        content: String?,
        toolCallID: String? = nil,
        toolName: String? = nil,
        args: AnyCodable? = nil
    ) {
        self.type = type
        self.content = content
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.args = args
    }

    enum CodingKeys: String, CodingKey {
        case type, content, args
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
    }
}

/// The kind of content carried by a ``ChatMessagePart``.
public enum ChatMessagePartType: String, Codable, Sendable {
    case text
    case toolCall = "tool_call"
    case toolResult = "tool_result"
}

/// Lifecycle status of a Coder Chat.
public enum ChatStatus: String, Codable, Sendable {
    case streaming
    case idle
    case actionRequired = "action_required"
    case complete
}

// MARK: - Chat Input Part

/// A typed chunk of content sent *to* a chat (as opposed to
/// ``ChatMessagePart`` which is received from the stream).
public struct ChatInputPart: Sendable {
    public let type: ChatMessagePartType
    public let text: String

    public static func text(_ text: String) -> ChatInputPart {
        ChatInputPart(type: .text, text: text)
    }
}

// MARK: - Tool Results

/// The result of executing a dynamic tool locally, sent back to the
/// Coder Chat so the LLM can continue.
public struct ToolResult: Codable, Sendable {
    public let toolCallID: String
    public let output: AnyCodable

    public init(toolCallID: String, output: AnyCodable) {
        self.toolCallID = toolCallID
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case output
    }
}

// MARK: - Model Configuration

/// An available LLM model configuration on the Coder deployment.
public struct ChatModel: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let provider: String

    public init(id: UUID, name: String, provider: String) {
        self.id = id
        self.name = name
        self.provider = provider
    }
}
