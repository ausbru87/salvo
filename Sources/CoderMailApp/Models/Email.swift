import Foundation

// MARK: - Email Address

struct EmailAddress: Identifiable, Hashable, Codable {
    var id: String { address }
    let displayName: String
    let address: String

    /// Formatted as "Display Name <address>" or just the address
    /// when no display name is available.
    var formatted: String {
        displayName.isEmpty ? address : "\(displayName) <\(address)>"
    }
}

// MARK: - Email Message

struct EmailMessage: Identifiable, Hashable, Codable {
    let id: String
    let threadID: String
    let from: EmailAddress
    let to: [EmailAddress]
    let cc: [EmailAddress]
    let bcc: [EmailAddress]
    let subject: String
    let body: String
    let snippet: String
    let date: Date
    let isRead: Bool
    let labels: [String]

    /// Gmail-style message ID header for threading.
    let messageIDHeader: String
    let inReplyTo: String?
    let references: [String]
}

// MARK: - Email Thread

struct EmailThread: Identifiable, Hashable, Codable {
    let id: String
    let subject: String
    let snippet: String
    let messages: [EmailMessage]
    let labels: [String]

    var lastMessageDate: Date {
        messages.last?.date ?? .distantPast
    }

    var isUnread: Bool {
        messages.contains { !$0.isRead }
    }

    /// Summarizes the sender names for the thread list row.
    var senderSummary: String {
        let uniqueSenders = messages.map(\.from.displayName)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) {
                    result.append(name)
                }
            }
        return uniqueSenders.joined(separator: ", ")
    }

    // Hashable conformance uses only the thread ID so SwiftUI
    // selection bindings work without comparing every message.
    static func == (lhs: EmailThread, rhs: EmailThread) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Attachment

struct EmailAttachment: Identifiable, Hashable, Codable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int

    var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(sizeBytes),
            countStyle: .file
        )
    }
}
