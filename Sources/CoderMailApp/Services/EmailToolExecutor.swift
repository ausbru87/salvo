import Foundation
import GmailAPI
import CoderAPI

// MARK: - EmailToolExecutor

/// Executes Coder Chat dynamic tool calls by reading from Gmail
/// and the local compose state.
///
/// The executor is intentionally *not* `@Observable`; it is owned
/// by the UI layer (or ``AIEmailService``) which pushes state
/// into the mutable properties before each execution round.
final class EmailToolExecutor {

    /// The Gmail client used for server-side operations like
    /// thread fetches and message searches.
    let gmailClient: any GmailClient

    // MARK: - Mutable state set by the caller

    /// The current body text in the compose editor.
    var currentDraftBody: String = ""

    /// The current subject line in the compose editor.
    var currentSubject: String = ""

    /// The thread being replied to, if any.
    var threadContext: EmailThreadContext?

    // MARK: - Init

    init(gmailClient: any GmailClient) {
        self.gmailClient = gmailClient
    }

    // MARK: - Public

    /// Dispatch a tool call by name, returning a ``ToolResult``
    /// that can be submitted back to the Coder Chat.
    ///
    /// - Parameters:
    ///   - toolName: The tool name emitted by the LLM.
    ///   - args: The JSON arguments decoded from the tool call.
    ///   - toolCallID: The server-assigned ID for this invocation.
    func execute(
        toolName: String,
        args: [String: Any],
        toolCallID: String = ""
    ) async throws -> ToolResult {
        let output: AnyCodable

        switch toolName {
        case "get_email_thread":
            output = try await executeGetEmailThread(args: args)
        case "get_current_draft":
            output = try await executeGetCurrentDraft(args: args)
        case "update_draft":
            output = try await executeUpdateDraft(args: args)
        case "set_subject":
            output = try await executeSetSubject(args: args)
        case "search_emails":
            output = try await executeSearchEmails(args: args)
        default:
            output = AnyCodable([
                "error": AnyCodable(
                    "Unknown tool: \(toolName)"
                )
            ])
        }

        return ToolResult(toolCallID: toolCallID, output: output)
    }

    // MARK: - Tool Implementations

    /// Return the thread context as a structured dictionary.
    ///
    /// If a ``threadContext`` snapshot is available it is used
    /// directly. Otherwise the executor falls back to fetching
    /// the thread from Gmail using the ``thread_id`` argument.
    private func executeGetEmailThread(
        args: [String: Any]
    ) async throws -> AnyCodable {
        // Prefer the local snapshot when available.
        if let ctx = threadContext {
            return formatThread(ctx)
        }

        // Fall back to a live Gmail fetch.
        guard let threadID = args["thread_id"] as? String else {
            return [
                "error": "Missing required argument: thread_id",
            ]
        }

        let thread = try await gmailClient.getThread(
            id: threadID, format: .full
        )

        return formatGmailThread(thread)
    }

    /// Return the current draft body and subject.
    private func executeGetCurrentDraft(
        args: [String: Any]
    ) async throws -> AnyCodable {
        [
            "body": AnyCodable(currentDraftBody),
            "subject": AnyCodable(currentSubject),
        ]
    }

    /// Replace the draft body with the provided text.
    private func executeUpdateDraft(
        args: [String: Any]
    ) async throws -> AnyCodable {
        guard let body = args["body"] as? String else {
            return ["error": "Missing required argument: body"]
        }
        currentDraftBody = body
        return ["status": "ok"]
    }

    /// Set the compose editor's subject line.
    private func executeSetSubject(
        args: [String: Any]
    ) async throws -> AnyCodable {
        guard let subject = args["subject"] as? String else {
            return ["error": "Missing required argument: subject"]
        }
        currentSubject = subject
        return ["status": "ok"]
    }

    /// Search Gmail messages matching a query and return compact
    /// summaries.
    private func executeSearchEmails(
        args: [String: Any]
    ) async throws -> AnyCodable {
        guard let query = args["query"] as? String else {
            return ["error": "Missing required argument: query"]
        }
        let maxResults = (args["max_results"] as? Int) ?? 5

        let listResponse = try await gmailClient.listMessages(
            query: query,
            maxResults: maxResults,
            pageToken: nil
        )

        guard let refs = listResponse.messages, !refs.isEmpty else {
            return ["results": [] as AnyCodable]
        }

        var results: [AnyCodable] = []
        for ref in refs.prefix(maxResults) {
            do {
                let msg = try await gmailClient.getMessage(
                    id: ref.id, format: .minimal
                )
                results.append([
                    "id": AnyCodable(msg.id),
                    "thread_id": AnyCodable(msg.threadId),
                    "snippet": AnyCodable(msg.snippet ?? ""),
                ])
            } catch {
                // Skip individual fetch failures so a single
                // missing message does not break the search.
                continue
            }
        }

        return ["results": AnyCodable(results)]
    }

    // MARK: - Formatting Helpers

    /// Convert a local ``EmailThreadContext`` into an
    /// ``AnyCodable`` dictionary.
    private func formatThread(
        _ ctx: EmailThreadContext
    ) -> AnyCodable {
        let iso = ISO8601DateFormatter()

        let messages: [AnyCodable] = ctx.messages.map { msg in
            [
                "from": AnyCodable(msg.from),
                "to": AnyCodable(msg.to.map { AnyCodable($0) }),
                "date": AnyCodable(iso.string(from: msg.date)),
                "body": AnyCodable(msg.body),
                "is_html": AnyCodable(msg.isHTML),
            ]
        }

        return [
            "thread_id": AnyCodable(ctx.threadID),
            "subject": AnyCodable(ctx.subject),
            "participants": AnyCodable(
                ctx.participants.map { AnyCodable($0) }
            ),
            "messages": AnyCodable(messages),
        ]
    }

    /// Convert a Gmail API ``GmailThread`` into an ``AnyCodable``
    /// dictionary suitable for returning to the LLM.
    ///
    /// Uses ``MessageParser`` from the GmailAPI module for header
    /// extraction and body decoding to avoid duplicating MIME
    /// logic.
    private func formatGmailThread(
        _ thread: GmailThread
    ) -> AnyCodable {
        let messages: [AnyCodable] =
            (thread.messages ?? []).map { msg in
                let from = MessageParser.extractHeader(
                    "From", from: msg
                ) ?? "unknown"
                let to = MessageParser.extractHeader(
                    "To", from: msg
                ) ?? ""
                let date = MessageParser.extractHeader(
                    "Date", from: msg
                ) ?? ""
                let subject = MessageParser.extractHeader(
                    "Subject", from: msg
                ) ?? ""
                let body = MessageParser.extractBody(
                    from: msg, preferHTML: false
                ) ?? msg.snippet ?? ""

                return [
                    "from": AnyCodable(from),
                    "to": AnyCodable(to),
                    "date": AnyCodable(date),
                    "subject": AnyCodable(subject),
                    "body": AnyCodable(body),
                    "snippet": AnyCodable(msg.snippet ?? ""),
                ]
            }

        return [
            "thread_id": AnyCodable(thread.id),
            "messages": AnyCodable(messages),
        ]
    }
}
