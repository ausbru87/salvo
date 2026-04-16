import Foundation

/// Interface to the Gmail REST API.
///
/// Concrete implementations handle OAuth token refresh, request
/// signing, and JSON decoding. The service layer depends only on
/// this protocol so it can be tested with fakes.
public protocol GmailClient: Sendable {
    /// Fetch the authenticated user's profile.
    func getProfile() async throws -> GmailProfile

    /// List messages matching an optional Gmail search query.
    func listMessages(
        query: String?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> MessageListResponse

    /// Fetch a single message by ID.
    func getMessage(
        id: String,
        format: MessageFormat?
    ) async throws -> GmailMessage

    /// Fetch a full thread by ID.
    func getThread(
        id: String,
        format: MessageFormat?
    ) async throws -> GmailThread

    /// List all labels for the authenticated user.
    func listLabels() async throws -> [GmailLabel]
}
