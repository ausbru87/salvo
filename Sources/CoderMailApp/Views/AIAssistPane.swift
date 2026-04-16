import SwiftUI

/// Side panel for AI-powered email assistance using the Coder Chats API.
/// Displays streaming LLM output and accepts user instructions.
struct AIAssistPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var instruction = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            streamingOutput
            Divider()
            inputBar
        }
        .background(.background.secondary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("AI Assist", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            if appState.aiChatState.isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
            Menu {
                Button("Clear Conversation") {
                    appState.aiChatState.clearConversation()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Streaming Output

    private var streamingOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appState.aiChatState.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.aiChatState.messages) { message in
                            AIChatBubble(message: message)
                                .id(message.id)
                        }

                        if appState.aiChatState.isStreaming {
                            streamingBubble
                                .id("streaming")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: appState.aiChatState.messages.count) {
                if let last = appState.aiChatState.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("AI Email Assistant")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask for help drafting, summarizing, or replying to emails.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.caption)
                .padding(.top, 2)
            Text(appState.aiChatState.streamingOutput)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this email…", text: $instruction)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendInstruction() }

            Button {
                sendInstruction()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(
                instruction.trimmingCharacters(in: .whitespaces).isEmpty
                    || appState.aiChatState.isStreaming
            )
        }
        .padding()
    }

    // MARK: - Actions

    private func sendInstruction() {
        let text = instruction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        appState.aiChatState.messages.append(
            AIChatMessage(role: .user, content: text)
        )
        instruction = ""

        // TODO: Send to Coder Chats API and stream response back.
        // CoderAPI.ChatClient will update aiChatState.streamingOutput
        // and append the final assistant message when complete.
    }
}

// MARK: - Chat Bubble

struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.caption)
                    .padding(.top, 2)
            }

            Text(message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.08)
        case .assistant: .purple.opacity(0.08)
        }
    }
}
