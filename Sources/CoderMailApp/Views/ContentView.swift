import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            MailboxSidebar(
                selectedMailbox: $appState.selectedMailbox
            )
        } content: {
            ThreadListView(
                threads: appState.threadsForSelectedMailbox,
                selectedThread: $appState.selectedThread
            )
        } detail: {
            if appState.isAIAssistVisible {
                HSplitView {
                    ThreadDetailView(thread: appState.selectedThread)
                    AIAssistPane()
                        .frame(minWidth: 280, idealWidth: 320)
                }
            } else {
                ThreadDetailView(thread: appState.selectedThread)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isComposePresented = true
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $appState.isAIAssistVisible) {
                    Label("AI Assist", systemImage: "sparkles")
                }
            }
        }
        .sheet(isPresented: $appState.isComposePresented) {
            ComposeView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Mailbox Sidebar

struct MailboxSidebar: View {
    @Binding var selectedMailbox: Mailbox?

    private let mailboxes: [Mailbox] = [
        Mailbox(id: "inbox", name: "Inbox", systemImage: "tray"),
        Mailbox(id: "starred", name: "Starred", systemImage: "star"),
        Mailbox(id: "sent", name: "Sent", systemImage: "paperplane"),
        Mailbox(id: "drafts", name: "Drafts", systemImage: "doc"),
        Mailbox(id: "archive", name: "Archive", systemImage: "archivebox"),
        Mailbox(id: "trash", name: "Trash", systemImage: "trash"),
    ]

    var body: some View {
        List(mailboxes, selection: $selectedMailbox) { mailbox in
            Label(mailbox.name, systemImage: mailbox.systemImage)
                .tag(mailbox)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 200)
    }
}

// MARK: - Thread List

struct ThreadListView: View {
    let threads: [EmailThread]
    @Binding var selectedThread: EmailThread?

    var body: some View {
        Group {
            if threads.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "tray",
                    description: Text("This mailbox is empty.")
                )
            } else {
                List(threads, selection: $selectedThread) { thread in
                    ThreadRow(thread: thread)
                        .tag(thread)
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 350)
    }
}

struct ThreadRow: View {
    let thread: EmailThread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.senderSummary)
                    .fontWeight(thread.isUnread ? .semibold : .regular)
                Spacer()
                Text(thread.lastMessageDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(thread.subject)
                .font(.headline)
                .lineLimit(1)
            Text(thread.snippet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thread Detail

struct ThreadDetailView: View {
    let thread: EmailThread?

    var body: some View {
        if let thread {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(thread.subject)
                        .font(.title2)
                        .fontWeight(.semibold)

                    ForEach(thread.messages) { message in
                        MessageView(message: message)
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Message Selected",
                systemImage: "envelope",
                description: Text("Select a thread to read.")
            )
        }
    }
}

struct MessageView: View {
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.from.displayName)
                    .fontWeight(.semibold)
                Text("<\(message.from.address)>")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !message.to.isEmpty {
                Text("To: \(message.to.map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(message.body)
                .textSelection(.enabled)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Types

struct Mailbox: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
}
