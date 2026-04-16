# CoderMail

A native macOS Gmail client that uses the [Coder Chats API](https://coder.com/docs) for AI-powered email drafting. Your data stays on your infrastructure, and you pick the model.

## Why

- **Gmail's Gemini Lite** is low quality with no model choice.
- **Third-party clients** (Superhuman, Spark) send your email to their servers and use proprietary agents.
- **Copy-paste to Claude/ChatGPT** loses the visual context of the email thread.

CoderMail keeps email CRUD on Gmail's API and routes all AI through your Coder deployment — Claude, GPT, or whatever model your admin configured.

## Architecture

```
┌──────────────────────────────────┐
│     CoderMail (macOS native)     │
│  ┌────────────┐ ┌──────────────┐ │
│  │  Email View │ │ AI Compose   │ │
│  │  (Gmail)    │ │ (Coder Chat) │ │
│  └──────┬─────┘ └──────┬───────┘ │
└─────────┼──────────────┼─────────┘
          │              │
     Gmail REST     Coder Chats API
     API (OAuth2)   (OAuth2 + PKCE)
                         │
                    Your Coder Deploy
                    (Claude / GPT / etc.)
```

**Dynamic Tools**: The app registers tools (`get_email_thread`, `get_current_draft`, `update_draft`) that the LLM calls. The app fulfills them locally — reading from Gmail or the compose editor — and returns results via `SubmitToolResults`. The model only sees email data you explicitly provide through tool calls.

**No workspace needed**: Chats are created without a `workspace_id`, so they run in the Coder control plane. No workspace spin-up latency for email tasks.

## Project Structure

```
Sources/
├── CoderMailApp/           # macOS app (SwiftUI)
│   ├── CoderMailApp.swift  # @main entry point
│   ├── Views/
│   │   ├── ContentView.swift     # Three-column NavigationSplitView
│   │   ├── ComposeView.swift     # Email compose with AI assist toggle
│   │   └── AIAssistPane.swift    # Streaming LLM output + instruction input
│   ├── Models/
│   │   ├── Email.swift           # EmailThread, EmailMessage types
│   │   └── AppState.swift        # Observable app-wide state
│   └── Services/
│       ├── AIEmailService.swift      # Orchestrates Coder Chats for email tasks
│       ├── AccountManager.swift      # Keychain credential management
│       └── EmailToolExecutor.swift   # Executes dynamic tool calls locally
├── CoderAPI/               # Coder Chats API client library
│   ├── CoderClient.swift   # HTTP + WebSocket client
│   ├── CoderOAuth.swift    # OAuth2 PKCE flow
│   ├── CoderAPIError.swift
│   └── Models/
│       ├── ChatTypes.swift # All Coder SDK types
│       └── AnyCodable.swift
└── GmailAPI/               # Gmail REST API client library
    ├── GmailClient.swift
    ├── GmailOAuth.swift
    ├── MessageParser.swift # MIME parsing, base64url decode
    └── Models/
        └── GmailTypes.swift
```

## Requirements

- macOS 14+ (Sonoma)
- Swift 5.9+
- Xcode 15+
- A Coder deployment with chat enabled
- A Google Cloud project with Gmail API enabled

## Setup

### 1. Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project, enable the Gmail API
3. Create OAuth 2.0 credentials (macOS app type)
4. Set redirect URI to `codermail://oauth/google/callback`
5. Note the Client ID

### 2. Coder OAuth Application (recommended)

If your Coder instance has the `oauth2` experiment enabled:

1. Go to Coder → Deployment Settings → OAuth2 Applications
2. Create an application with callback URL `codermail://oauth/coder/callback`
3. Note the Client ID

Or use a session token (Settings → API Tokens in the app).

### 3. Build & Run

```bash
# Clone
git clone <this-repo>
cd codermail

# Open in Xcode
open Package.swift

# Or build from CLI
swift build
```

## AI Features

| Feature | How it works |
|---------|-------------|
| **Reply Assist** | Creates a chat, model calls `get_email_thread` → reads Gmail → streams draft |
| **Refine Draft** | Follow-up messages: "make it shorter", "more formal", etc. |
| **Subject Lines** | One-shot chat reads draft body, suggests 3 options |
| **Thread Summary** | Summarizes long threads: decisions, action items, open questions |
| **Tone Adjust** | Select text → pick tone → model rewrites in-place |

## Privacy

- Email data is sent to **your Coder instance only** (not a third-party SaaS)
- Data flows through dynamic tool calls you control — you can filter/redact
- Chat retention follows your Coder deployment's retention policy
- All tokens stored in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)

## License

MIT
