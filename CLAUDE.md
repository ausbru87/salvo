# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                        # Build all targets
swift test                         # Run all tests (requires Xcode.app)
swift test --filter CoderAPITests  # Run tests in a specific target
swift test --filter TestClassName  # Run a specific test class
open Package.swift                 # Open in Xcode
```

Requirements: macOS 14+, Swift 5.9+. `swift build` works with CLI tools only. `swift test` requires Xcode.app — macOS SPM wraps tests in `.xctest` bundles that need the `xctest` runner, which ships with Xcode.app, not the CLI tools. After installing Xcode, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

Tests use [Swift Testing](https://developer.apple.com/xcode/swift-testing/) (`import Testing`, `@Test`, `#expect`).

## Architecture

Salvo is a native macOS Gmail client that routes all AI through a [Coder](https://coder.com) deployment. Email CRUD stays on the Gmail API; AI inference goes through the Coder Chats API. The two paths never cross.

### Layer Structure

Three SPM targets with a clear dependency order:

```
SalvoApp  →  CoderAPI  (Coder Chats HTTP + WebSocket client)
          →  GmailAPI  (Gmail REST + MIME parsing)
```

**`CoderAPI`** — protocol-first library (`CoderClient.swift`). Defines `createChat`, `streamChat`, `submitToolResults`, `archiveChat`, `listModels`. Streaming is WebSocket-based, returning `AsyncThrowingStream<ChatStreamEvent, Error>`. `CoderOAuth.swift` implements OAuth2 PKCE; `ChatTypes.swift` holds all request/response models.

**`GmailAPI`** — protocol-first library (`GmailClient.swift`). Covers `getProfile`, `listMessages`, `getMessage`, `getThread`, `listLabels`. `MessageParser.swift` handles MIME and base64url decoding. `GmailOAuth.swift` handles Google OAuth2.

**`SalvoApp`** — the executable. Three sub-layers:
- **Views** (`ContentView`, `ComposeView`, `AIAssistPane`): SwiftUI, three-column `NavigationSplitView`.
- **Models** (`Email.swift`, `AppState.swift`): Data types + `@Observable` app state.
- **Services** (`AIEmailService`, `AccountManager`, `EmailToolExecutor`): Business logic, Keychain, tool dispatch.

### Dynamic Tools — The Core Pattern

The architecturally interesting part: the LLM has no direct access to Gmail. Instead, `AIEmailService` registers tools (`get_email_thread`, `get_current_draft`, `update_draft`, `set_subject`) with the chat. When the model needs email data, it calls a tool; the app intercepts the `action_required` stream event, executes locally (reads from Gmail API or compose editor), and returns results via `submitToolResults`. The model only sees data that passes through these controlled tool calls.

Tool execution loop in `AIEmailService`:
1. `startReplyAssist` → `createChat` with tools + system prompt
2. Stream delivers `statusChange(.actionRequired)` with tool call
3. `EmailToolExecutor` runs the tool locally
4. `submitToolResults` → stream resumes
5. Repeat until `done`

### Chat Lifecycle

One Coder chat per email action (reply, compose, summarize, subject lines). Chats run without a `workspace_id` — they execute in the Coder control plane with no workspace spin-up latency. Chats are archived via `finishSession()` when the action completes.

### State Management

`@Observable` + `@MainActor` throughout (Swift 5.9 observation). `AppState` owns navigation and AI session state. `AIEmailService` owns streaming state (`isStreaming`, `currentDraft`, `streamedParts`, `pendingToolCalls`). `AccountManager` owns Keychain-backed credentials (Coder session token + Gmail OAuth tokens).

### Auth

- **Coder**: OAuth2 PKCE via `ASWebAuthenticationSession` (redirect URI `salvo://oauth/coder/callback`). Session token fallback for deployments without the `oauth2` experiment.
- **Gmail**: Google OAuth2 (redirect URI `salvo://oauth/google/callback`).
- **Storage**: All tokens in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
