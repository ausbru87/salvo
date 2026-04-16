import Foundation
import Observation
import CoderAPI

// MARK: - AIEmailService

/// Orchestrates Coder Chat sessions for email-assistance workflows.
///
/// Each user-facing action (reply assist, tone adjustment, …) maps
/// to one or more Coder Chat round-trips. Streamed text is
/// accumulated in observable properties so SwiftUI views can bind
/// directly.
@Observable
@MainActor
final class AIEmailService {

    // MARK: - Observable state

    /// Whether the service is currently receiving streamed tokens.
    var isStreaming = false

    /// The accumulated draft body produced by the LLM.
    var currentDraft = ""

    /// The current subject line, set via the ``set_subject`` tool.
    var currentSubject = ""

    /// Every message part received during the active stream.
    var streamedParts: [ChatMessagePart] = []

    /// A human-readable error message, or `nil` when healthy.
    var error: String?

    /// Tool calls awaiting local execution before the LLM can
    /// continue.
    var pendingToolCalls: [PendingToolCall] = []

    // MARK: - Private state

    @ObservationIgnored private let coderClient: any CoderClient
    @ObservationIgnored private var activeChatID: UUID?
    @ObservationIgnored private var activeThread: EmailThreadContext?
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init(coderClient: any CoderClient) {
        self.coderClient = coderClient
    }

    // MARK: - Email Actions

    /// Start a reply-assist flow.
    ///
    /// Creates a Coder Chat with email-aware dynamic tools, sends
    /// the user's instruction together with thread metadata, and
    /// begins streaming the LLM response. Streamed text is
    /// accumulated into ``currentDraft``.
    func startReplyAssist(
        instruction: String,
        thread: EmailThreadContext,
        organizationID: UUID,
        modelConfigID: UUID? = nil
    ) async throws {
        streamTask?.cancel()
        resetState()
        activeThread = thread

        let request = CreateChatRequest(
            modelConfigID: modelConfigID,
            systemPrompt: Self.emailAssistantPrompt,
            dynamicTools: emailDynamicTools()
        )

        let chat = try await coderClient.createChat(
            organizationID: organizationID,
            request: request
        )
        activeChatID = chat.id

        let userMessage = buildReplyInstruction(
            instruction: instruction,
            thread: thread
        )
        let stream = try await coderClient.streamChat(
            chatID: chat.id,
            message: userMessage
        )

        // Stream processing runs in a detachable task so the
        // caller returns as soon as chat creation succeeds.
        streamTask = Task { [weak self] in
            do {
                try await self?.processStream(stream)
            } catch is CancellationError {
                // Normal cancellation — nothing to report.
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    /// Send a follow-up refinement to the current chat
    /// ("make it shorter", "more formal", etc.).
    func refineCurrentDraft(instruction: String) async throws {
        guard let chatID = activeChatID else {
            throw AIEmailServiceError.noActiveChat
        }
        streamTask?.cancel()
        error = nil
        streamedParts = []

        let stream = try await coderClient.streamChat(
            chatID: chatID,
            message: instruction
        )

        streamTask = Task { [weak self] in
            do {
                try await self?.processStream(stream)
            } catch is CancellationError {
                // Normal.
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    /// Generate subject line suggestions for a draft body.
    func suggestSubjectLines(
        draftBody: String,
        organizationID: UUID
    ) async throws -> [String] {
        let prompt = """
            Based on this email draft, suggest 5 concise subject \
            lines. Return each on its own line, numbered 1-5. \
            Nothing else.

            Draft:
            \(draftBody)
            """

        let response = try await runOneShot(
            systemPrompt: "You suggest email subject lines. "
                + "Be concise and specific.",
            message: prompt,
            organizationID: organizationID
        )

        return parseNumberedList(response)
    }

    /// Summarize an email thread in 2-3 sentences.
    func summarizeThread(
        thread: EmailThreadContext,
        organizationID: UUID
    ) async throws -> String {
        let threadText = formatThreadForPrompt(thread)
        let prompt = """
            Summarize this email thread in 2-3 sentences. Focus \
            on the key points and any action items.

            \(threadText)
            """

        return try await runOneShot(
            systemPrompt: "You summarize email threads concisely.",
            message: prompt,
            organizationID: organizationID
        )
    }

    /// Rewrite selected text to match the requested tone.
    func adjustTone(
        selectedText: String,
        tone: ToneSetting,
        organizationID: UUID
    ) async throws -> String {
        let prompt = """
            Rewrite this text with a \(tone.rawValue) tone. Keep \
            the same meaning and length. Return only the rewritten \
            text.

            Text:
            \(selectedText)
            """

        return try await runOneShot(
            systemPrompt: "You rewrite text to match a requested "
                + "tone.",
            message: prompt,
            organizationID: organizationID
        )
    }

    /// Cancel the current streaming operation.
    func interrupt() async throws {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// Clean up: archive the active chat and clear local state.
    func finishSession() async throws {
        try await interrupt()
        if let chatID = activeChatID {
            try await coderClient.archiveChat(chatID: chatID)
        }
        activeChatID = nil
        activeThread = nil
    }

    // MARK: - Dynamic Tools

    /// Build the dynamic tool definitions that give the LLM
    /// read/write access to the compose editor and the email
    /// thread.
    private func emailDynamicTools() -> [DynamicTool] {
        [
            DynamicTool(
                name: "get_email_thread",
                description: "Retrieve the email thread being "
                    + "replied to",
                schema: [
                    "type": "object",
                    "properties": [
                        "thread_id": [
                            "type": "string",
                            "description": "The Gmail thread ID",
                        ] as AnyCodable,
                    ] as AnyCodable,
                    "required": ["thread_id"] as AnyCodable,
                ]
            ),
            DynamicTool(
                name: "get_current_draft",
                description: "Get the current draft text in the "
                    + "compose editor",
                schema: [
                    "type": "object",
                    "properties": [:] as AnyCodable,
                ]
            ),
            DynamicTool(
                name: "update_draft",
                description: "Replace the draft body in the "
                    + "compose editor",
                schema: [
                    "type": "object",
                    "properties": [
                        "body": [
                            "type": "string",
                            "description": "The new draft body",
                        ] as AnyCodable,
                    ] as AnyCodable,
                    "required": ["body"] as AnyCodable,
                ]
            ),
            DynamicTool(
                name: "set_subject",
                description: "Set the email subject line",
                schema: [
                    "type": "object",
                    "properties": [
                        "subject": [
                            "type": "string",
                            "description": "The subject line",
                        ] as AnyCodable,
                    ] as AnyCodable,
                    "required": ["subject"] as AnyCodable,
                ]
            ),
        ]
    }

    // MARK: - Stream Processing

    /// Consume a stream of ``ChatStreamEvent``s, accumulating text
    /// into ``currentDraft`` and handling tool-call round-trips.
    ///
    /// When the LLM requests tool execution the method runs the
    /// tools locally, submits results, and recursively processes
    /// the continuation stream.
    private func processStream(
        _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
    ) async throws {
        isStreaming = true

        for try await event in stream {
            try Task.checkCancellation()

            switch event {
            case .messagePart(let part):
                handleMessagePart(part)

            case .statusChange(let status):
                try await handleStatusChange(status)
                if status == .actionRequired {
                    // The recursive call inside handleStatusChange
                    // processes the continuation. Exit this loop.
                    return
                }

            case .error(let message):
                self.error = message
                isStreaming = false

            case .done:
                isStreaming = false
            }
        }

        isStreaming = false
    }

    /// Append a message part to observable state and record any
    /// tool calls.
    private func handleMessagePart(_ part: ChatMessagePart) {
        streamedParts.append(part)

        switch part.type {
        case .text:
            if let content = part.content {
                currentDraft += content
            }

        case .toolCall:
            if let id = part.toolCallID, let name = part.toolName {
                let args =
                    (part.args?.value as? [String: Any]) ?? [:]
                pendingToolCalls.append(
                    PendingToolCall(
                        id: id, toolName: name, args: args
                    )
                )
            }

        case .toolResult:
            // Echoed results from the server — nothing to do.
            break
        }
    }

    /// React to a chat status transition.
    private func handleStatusChange(
        _ status: ChatStatus
    ) async throws {
        switch status {
        case .actionRequired:
            try await executeAndSubmitToolCalls()

        case .complete, .idle:
            isStreaming = false

        case .streaming:
            isStreaming = true
        }
    }

    // MARK: - Tool Execution

    /// Execute every pending tool call, submit the results, and
    /// process the continuation stream.
    private func executeAndSubmitToolCalls() async throws {
        var results: [ToolResult] = []

        for call in pendingToolCalls {
            let context = ToolContext(
                thread: activeThread,
                currentDraft: currentDraft
            )
            let output = handleToolCall(
                name: call.toolName,
                args: call.args,
                context: context
            )
            results.append(
                ToolResult(toolCallID: call.id, output: output)
            )
        }
        pendingToolCalls = []

        guard let chatID = activeChatID else { return }
        let continuation = try await coderClient.submitToolResults(
            chatID: chatID,
            results: results
        )
        try await processStream(continuation)
    }

    /// Execute a single tool call locally and return the result
    /// payload.
    private func handleToolCall(
        name: String,
        args: [String: Any],
        context: ToolContext
    ) -> AnyCodable {
        switch name {
        case "get_email_thread":
            guard let thread = context.thread else {
                return ["error": "No thread context available"]
            }
            return formatThreadAsAnyCodable(thread)

        case "get_current_draft":
            return [
                "body": AnyCodable(context.currentDraft),
                "subject": AnyCodable(currentSubject),
            ]

        case "update_draft":
            if let body = args["body"] as? String {
                currentDraft = body
            }
            return ["status": "ok"]

        case "set_subject":
            if let subject = args["subject"] as? String {
                currentSubject = subject
            }
            return ["status": "ok"]

        default:
            return [
                "error": AnyCodable("Unknown tool: \(name)")
            ]
        }
    }

    // MARK: - One-Shot Helpers

    /// Run a throwaway chat that collects the full response and
    /// archives itself.
    private func runOneShot(
        systemPrompt: String,
        message: String,
        organizationID: UUID
    ) async throws -> String {
        let request = CreateChatRequest(
            modelConfigID: nil,
            systemPrompt: systemPrompt,
            dynamicTools: nil
        )
        let chat = try await coderClient.createChat(
            organizationID: organizationID,
            request: request
        )

        defer {
            let client = coderClient
            let id = chat.id
            Task { try? await client.archiveChat(chatID: id) }
        }

        let stream = try await coderClient.streamChat(
            chatID: chat.id,
            message: message
        )

        var result = ""
        for try await event in stream {
            if case .messagePart(let part) = event,
                part.type == .text,
                let content = part.content
            {
                result += content
            }
        }

        return result
    }

    // MARK: - Formatting

    private func buildReplyInstruction(
        instruction: String,
        thread: EmailThreadContext
    ) -> String {
        """
        I need help replying to an email thread.

        Subject: \(thread.subject)
        Participants: \(thread.participants.joined(separator: ", "))

        My instruction: \(instruction)

        Use the get_email_thread tool to read the full \
        conversation, then use update_draft to write your draft.
        """
    }

    private func formatThreadForPrompt(
        _ thread: EmailThreadContext
    ) -> String {
        var lines: [String] = [
            "Subject: \(thread.subject)",
            "Participants: "
                + thread.participants.joined(separator: ", "),
            "",
        ]

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        for msg in thread.messages {
            lines.append("From: \(msg.from)")
            lines.append(
                "To: \(msg.to.joined(separator: ", "))"
            )
            lines.append(
                "Date: \(formatter.string(from: msg.date))"
            )
            lines.append("")
            lines.append(msg.body)
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    private func formatThreadAsAnyCodable(
        _ thread: EmailThreadContext
    ) -> AnyCodable {
        let iso = ISO8601DateFormatter()
        let messages: [AnyCodable] = thread.messages.map { msg in
            [
                "from": AnyCodable(msg.from),
                "to": AnyCodable(
                    msg.to.map { AnyCodable($0) }
                ),
                "date": AnyCodable(
                    iso.string(from: msg.date)
                ),
                "body": AnyCodable(msg.body),
            ]
        }

        return [
            "thread_id": AnyCodable(thread.threadID),
            "subject": AnyCodable(thread.subject),
            "participants": AnyCodable(
                thread.participants.map { AnyCodable($0) }
            ),
            "messages": AnyCodable(messages),
        ]
    }

    /// Parse a numbered list ("1. Foo\n2. Bar") into bare strings.
    private func parseNumberedList(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(
                        of: #"^\d+[\.\)]\s*"#,
                        with: "",
                        options: .regularExpression
                    )
            }
            .filter { !$0.isEmpty }
    }

    private func resetState() {
        isStreaming = false
        currentDraft = ""
        currentSubject = ""
        streamedParts = []
        error = nil
        pendingToolCalls = []
    }

    // MARK: - System Prompt

    private static let emailAssistantPrompt = """
        You are an email assistant integrated into a macOS email \
        client. You help draft, refine, and improve emails.

        Rules:
        - Write in the user's voice based on context from their \
        previous emails.
        - Keep emails concise unless asked otherwise.
        - Use the get_email_thread tool to read the conversation \
        before drafting.
        - Use update_draft to write your draft into the compose \
        editor.
        - Do not add fake signatures or closings unless the \
        user's style shows them.
        """
}

// MARK: - Supporting Types

/// Tone presets for the ``adjustTone`` action.
enum ToneSetting: String, CaseIterable, Sendable {
    case professional = "professional and polished"
    case casual = "casual and friendly"
    case direct = "direct and concise"
    case empathetic = "warm and empathetic"
    case formal = "formal and respectful"
}

/// Lightweight snapshot of an email thread passed into AI actions.
struct EmailThreadContext: Sendable {
    let threadID: String
    let messages: [EmailMessageContext]
    let subject: String
    /// Email addresses of every participant.
    let participants: [String]
}

/// A single message inside an ``EmailThreadContext``.
struct EmailMessageContext: Sendable {
    let from: String
    let to: [String]
    let date: Date
    let body: String
    let isHTML: Bool
}

/// A tool call the LLM has requested but that has not yet been
/// executed locally.
struct PendingToolCall {
    let id: String
    let toolName: String
    let args: [String: Any]
}

/// Read-only snapshot handed to tool executors so they can answer
/// questions about the current compose state.
struct ToolContext: Sendable {
    let thread: EmailThreadContext?
    let currentDraft: String
}

/// Errors specific to ``AIEmailService``.
enum AIEmailServiceError: Error, LocalizedError {
    case noActiveChat

    var errorDescription: String? {
        switch self {
        case .noActiveChat:
            return "No active chat session. Start a new "
                + "reply-assist flow first."
        }
    }
}
