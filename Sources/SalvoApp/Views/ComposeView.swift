import SwiftUI

struct ComposeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var to = ""
    @State private var cc = ""
    @State private var subject = ""
    @State private var emailBody = ""
    @State private var showCC = false
    @State private var isAIAssistVisible = false
    @State private var aiInstruction = ""

    var body: some View {
        HSplitView {
            composeForm
                .frame(minWidth: 480, idealWidth: 560)

            if isAIAssistVisible {
                composeAIPane
                    .frame(minWidth: 260, idealWidth: 300)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    // MARK: - Compose Form

    private var composeForm: some View {
        VStack(spacing: 0) {
            // Header fields.
            VStack(spacing: 8) {
                HStack {
                    Text("To:")
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("Recipients", text: $to)
                        .textFieldStyle(.plain)
                }
                if showCC {
                    HStack {
                        Text("CC:")
                            .frame(width: 60, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        TextField("CC Recipients", text: $cc)
                            .textFieldStyle(.plain)
                    }
                }
                HStack {
                    Text("Subject:")
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("Subject", text: $subject)
                        .textFieldStyle(.plain)
                }
            }
            .padding()

            Divider()

            // Body editor.
            TextEditor(text: $emailBody)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)

            Divider()

            // Toolbar.
            HStack {
                Button {
                    showCC.toggle()
                } label: {
                    Text("CC")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    isAIAssistVisible.toggle()
                } label: {
                    Label("AI Assist", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Discard") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Send") {
                    // TODO: Send via GmailAPI.
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    // MARK: - Inline AI Pane

    private var composeAIPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Drafting Assistant", systemImage: "sparkles")
                .font(.headline)

            ScrollView {
                Text(appState.aiChatState.streamingOutput.isEmpty
                    ? "Ask the AI to help draft your email. For example:\n\n• \"Write a professional reply declining this meeting\"\n• \"Make this more concise\"\n• \"Translate to Spanish\""
                    : appState.aiChatState.streamingOutput)
                    .foregroundStyle(
                        appState.aiChatState.streamingOutput.isEmpty
                            ? .secondary : .primary
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                TextField("Ask AI to help…", text: $aiInstruction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendAIInstruction()
                    }

                Button {
                    sendAIInstruction()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(aiInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(.background.secondary)
    }

    private func sendAIInstruction() {
        let instruction = aiInstruction.trimmingCharacters(in: .whitespaces)
        guard !instruction.isEmpty else { return }
        // TODO: Send instruction to Coder Chats API with email context.
        aiInstruction = ""
    }
}
