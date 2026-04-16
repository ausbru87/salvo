# Salvo

A native macOS Gmail client that uses the [Coder Chats API](https://coder.com/docs) for AI-powered email drafting. Your data stays on your infrastructure, and you pick the model.

## Why

- **Gmail's Gemini Lite** is low quality with no model choice.
- **Third-party clients** (Superhuman, Spark) send your email to their servers and use proprietary agents.
- **Copy-paste to Claude/ChatGPT** loses the visual context of the email thread.

Salvo keeps email CRUD on Gmail's API and routes all AI through your Coder deployment — Claude, GPT, or whatever model your admin configured.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Salvo (macOS native)                     │
│                                                             │
│  ┌──────────────────────┐   ┌───────────────────────────┐   │
│  │     Email View       │   │     AI Compose Pane       │   │
│  │   ContentView.swift  │   │    AIAssistPane.swift     │   │
│  └──────────┬───────────┘   └──────────────┬────────────┘   │
│             │         Services              │               │
│  ┌──────────▼───────────┐   ┌──────────────▼────────────┐   │
│  │    GmailAPI module   │   │      CoderAPI module      │   │
│  │  HTTPGmailClient     │   │    HTTPCoderClient        │   │
│  │  URLSession (REST)   │   │  URLSession (HTTP + WSS)  │   │
│  │  Bearer + refresh    │   │  Session token or OAuth2  │   │
│  └──────────┬───────────┘   └──────────────┬────────────┘   │
└─────────────┼─────────────────────────────┼────────────────┘
              │                             │
    HTTPS + OAuth2 Bearer        HTTPS (create, message, tools)
    401 → auto token refresh     WSS  (stream events)
              │                             │
              ▼                             ▼
   Gmail REST API                Coder Chats API
   googleapis.com                /api/experimental/chats/*
                                            │
                                  Your Coder Deployment
                                  (Claude / GPT / custom)
```

**Dynamic Tools** — the privacy boundary: the app registers five tools (`get_email_thread`, `get_current_draft`, `update_draft`, `set_subject`, `search_emails`) with each chat. The LLM calls them when it needs data; the app intercepts the `action_required` WebSocket event, executes the tool locally against Gmail or the compose editor, and returns results via `SubmitToolResults`. The model only ever sees what passes through these controlled calls.

**No workspace needed**: Chats run in the Coder control plane — `workspace_id` is omitted, so there is no workspace spin-up latency for email tasks.

## Project Structure

```
Sources/
├── SalvoApp/                      # macOS app target (SwiftUI + AppKit)
│   ├── SalvoApp.swift             # @main entry point
│   ├── Views/
│   │   ├── ContentView.swift      # Three-column NavigationSplitView
│   │   ├── ComposeView.swift      # Email compose with AI assist toggle
│   │   └── AIAssistPane.swift     # Streaming LLM output + instruction input
│   ├── Models/
│   │   ├── Email.swift            # EmailThread, EmailMessage, EmailAddress
│   │   └── AppState.swift         # @Observable app-wide state
│   └── Services/
│       ├── AIEmailService.swift   # Orchestrates Coder Chats; drives tool loop
│       ├── AccountManager.swift   # Keychain credential storage
│       └── EmailToolExecutor.swift # Executes dynamic tool calls locally
├── CoderAPI/                      # SPM library — Coder Chats client
│   ├── CoderClient.swift          # Protocol (5 methods)
│   ├── HTTPCoderClient.swift      # URLSession + URLSessionWebSocketTask impl
│   ├── CoderStreamMessage.swift   # Wire-format decoder (WS JSON → ChatStreamEvent)
│   ├── HTTPHelpers.swift          # Request building, auth, error mapping, codec
│   ├── CoderOAuth.swift           # OAuth2 PKCE helpers + token exchange
│   ├── CoderAPIError.swift        # Typed error enum
│   └── Models/
│       ├── ChatTypes.swift        # Chat, CreateChatRequest, ChatStreamEvent, …
│       └── AnyCodable.swift       # Type-erased JSON value
└── GmailAPI/                      # SPM library — Gmail REST client
    ├── GmailClient.swift          # Protocol (5 methods)
    ├── HTTPGmailClient.swift      # URLSession impl; GmailTokenStore actor
    ├── GmailOAuth.swift           # Google OAuth2 helpers + token refresh
    ├── MessageParser.swift        # MIME tree walker, base64url decode
    └── Models/
        └── GmailTypes.swift       # GmailMessage, GmailThread, GmailLabel, …
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
4. Set redirect URI to `salvo://oauth/google/callback`
5. Note the Client ID

### 2. Coder OAuth Application (recommended)

If your Coder instance has the `oauth2` experiment enabled:

1. Go to Coder → Deployment Settings → OAuth2 Applications
2. Create an application with callback URL `salvo://oauth/coder/callback`
3. Note the Client ID

Or use a session token (Settings → API Tokens in the app).

### 3. Build & Run

```bash
# Clone
git clone <this-repo>
cd salvo

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
