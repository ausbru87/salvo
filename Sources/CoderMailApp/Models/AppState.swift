import Foundation
import SwiftUI

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    // Navigation.
    @Published var selectedMailbox: Mailbox? = Mailbox(
        id: "inbox", name: "Inbox", systemImage: "tray"
    )
    @Published var selectedThread: EmailThread?
    @Published var isComposePresented = false
    @Published var isAIAssistVisible = false

    // Data.
    @Published var accounts: [Account] = []
    @Published var threads: [EmailThread] = []

    // AI chat.
    @Published var aiChatState = AIChatState()

    /// Returns threads that belong to the currently selected mailbox.
    var threadsForSelectedMailbox: [EmailThread] {
        guard let mailbox = selectedMailbox else { return [] }
        return threads.filter { $0.labels.contains(mailbox.id) }
    }
}

// MARK: - Account

struct Account: Identifiable, Hashable {
    let id: String
    let emailAddress: String
    let displayName: String

    /// Base URL for the Coder deployment this account is linked to.
    let coderURL: URL?
    /// Session token for the Coder API.
    let coderSessionToken: String?
}

// MARK: - AI Chat State

struct AIChatState {
    var messages: [AIChatMessage] = []
    var streamingOutput: String = ""
    var isStreaming: Bool = false
    var chatID: String?

    mutating func clearConversation() {
        messages.removeAll()
        streamingOutput = ""
        isStreaming = false
        chatID = nil
    }
}

// MARK: - AI Chat Message

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: AIChatRole
    let content: String
}

enum AIChatRole {
    case user
    case assistant
}
