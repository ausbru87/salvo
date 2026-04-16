# macOS Gmail Client powered by Coder Chats API

## Problem Statement

Current options for AI-assisted email all suck in different ways:

1. **Gmail's Gemini Lite** — low quality, no model choice, locked into Google's ecosystem.
2. **Third-party email clients (Superhuman, Spark, etc.)** — send your email data to their proprietary servers, use their own opaque agents, no control over the model or prompts.
3. **Copy-paste to Claude/ChatGPT** — context-switching hell. You lose the visual context of the email thread, can't iterate inline, and can't see the draft alongside the conversation.

**The gap**: A native email client where AI assistance runs through infrastructure *you* control, using the model *you* pick, with your data staying in *your* Coder deployment.

---

## Core Architecture

```
┌─────────────────────────────────────────────┐
│              macOS Native App               │
│  (SwiftUI + AppKit)                         │
│                                             │
│  ┌──────────────┐   ┌────────────────────┐  │
│  │  Email View   │   │  AI Compose Pane  │  │
│  │  (Gmail API)  │   │  (Coder Chats)    │  │
│  │              │◄──►│                    │  │
│  │  - Inbox     │   │  - Draft assist    │  │
│  │  - Threads   │   │  - Subject lines   │  │
│  │  - Labels    │   │  - Tone rewrite    │  │
│  │  - Search    │   │  - Reply suggest   │  │
│  └──────────────┘   └────────────────────┘  │
│         │                     │              │
└─────────┼─────────────────────┼──────────────┘
          │                     │
          ▼                     ▼
   Gmail API (IMAP/REST)   Coder Chats API
   (email CRUD only)       (AI inference only)
                                │
                                ▼
                     ┌─────────────────────┐
                     │  Your Coder Deploy  │
                     │  ┌───────────────┐  │
                     │  │ Claude / GPT / │  │
                     │  │ any configured │  │
                     │  │ model          │  │
                     │  └───────────────┘  │
                     └─────────────────────┘
```

**Key principle**: Gmail API handles email transport/storage. Coder Chats API handles all AI. They never cross. Your email content is sent to your Coder instance (which you control) — not to a third-party SaaS.

---

## Coder Chats API — What's Available

Based on the current API surface (`/api/experimental/chats/*`):

### Relevant Endpoints

| Endpoint | Use in Email Client |
|----------|-------------------|
| `POST /chats` (CreateChat) | Start a new AI session for a compose/reply flow |
| `POST /chats/{id}/messages` (CreateChatMessage) | Send follow-up refinements ("make it more formal") |
| `WS /chats/{id}/stream` (StreamChat) | Stream the draft as it's being written, token by token |
| `PATCH /chats/{id}/messages/{mid}` (EditChatMessage) | Edit a previous instruction and re-generate |
| `POST /chats/{id}/interrupt` (InterruptChat) | Cancel mid-generation if it's going wrong |
| `GET /chats/models` (ListChatModels) | Let user pick Claude vs GPT vs whatever's configured |
| `POST /chats/{id}/tool-results` (SubmitToolResults) | Return email context to the model via dynamic tools |

### Key Features to Leverage

**1. System Prompts (per-chat)**
`CreateChatRequest.SystemPrompt` — set a system prompt tailored to email composition. Different prompts for:
- Composing new emails
- Replying to threads
- Summarizing long threads
- Generating subject lines

**2. UnsafeDynamicTools (client-side tool execution)**
This is the killer feature. The app registers tools that the LLM can call, and the app fulfills them locally:

```
DynamicTools the app would register:
├── get_email_thread      — fetch the full thread being replied to
├── get_current_draft     — read what the user has typed so far
├── get_contact_info      — pull sender/recipient context
├── get_recent_emails     — context from recent conversation with this person
├── update_draft          — write directly into the compose field
├── set_subject_line      — update the subject
├── add_recipients        — modify To/CC/BCC
└── search_emails         — find relevant past emails for context
```

The model calls `get_email_thread`, the app intercepts it, reads from Gmail API locally, and returns the thread content via `SubmitToolResults`. The model never sees data it shouldn't — it only sees what the registered tools provide when called.

**3. Labels on Chats**
`CreateChatRequest.Labels` — tag chats by email thread ID, contact, etc. for later retrieval/audit.

**4. Streaming**
`StreamChat` WebSocket — stream the draft token-by-token into the compose pane. User sees the draft being written in real time and can interrupt or steer.

**5. Model Selection**
`ListChatModels` — let the user pick the model per-task. Maybe Claude for nuanced replies, GPT-4o for quick one-liners, a fast model for subject lines.

---

## UX Flows

### Flow 1: Reply Assist (the core loop)

```
User clicks "Reply" on an email
    │
    ▼
App opens split view: [Email Thread | AI Compose Pane]
    │
    ▼
App calls CreateChat with:
  - system_prompt: "You are an email assistant. Help draft replies..."
  - content: [user's initial instruction, e.g. "decline politely"]
  - unsafe_dynamic_tools: [get_email_thread, get_current_draft, update_draft, ...]
  - labels: {"thread_id": "...", "flow": "reply"}
    │
    ▼
Model calls get_email_thread tool → app fetches from Gmail → returns via SubmitToolResults
    │
    ▼
Model streams draft into compose pane via StreamChat WebSocket
    │
    ▼
User reads draft, types "make the second paragraph less formal"
    │
    ▼
App calls CreateChatMessage with the refinement
    │
    ▼
Model calls get_current_draft tool → gets latest text → streams updated version
    │
    ▼
User is satisfied → hits Send (Gmail API directly)
```

### Flow 2: Quick Subject Line

```
User is composing, body is written, subject is blank
    │
    ▼
User clicks "✨ Suggest Subject" button
    │
    ▼
App creates short-lived chat with:
  - system_prompt: "Generate 3 concise email subject lines..."
  - dynamic tool: get_current_draft
    │
    ▼
Model calls get_current_draft → reads compose body
    │
    ▼
Returns 3 options → user picks one → chat is archived
```

### Flow 3: Thread Summary

```
User opens a long thread (20+ messages)
    │
    ▼
App shows "Summarize" button in toolbar
    │
    ▼
CreateChat with thread content via dynamic tools
    │
    ▼
Model returns structured summary:
  - Key decisions
  - Action items
  - Open questions
  - Timeline of events
```

### Flow 4: Tone Adjustment (inline)

```
User selects a paragraph in their draft
    │
    ▼
Right-click → "Adjust Tone" → [Professional | Casual | Direct | Empathetic]
    │
    ▼
App sends CreateChatMessage with selected text + tone instruction
    │
    ▼
Model streams replacement text → app substitutes in-place
```

---

## Technical Decisions to Think Through

### 1. Gmail Integration: Gmail REST API ✅

Gmail REST API with OAuth2. Use Google's push notifications (Pub/Sub)
for real-time inbox updates.

### 2. Chat Lifecycle: One chat per action ✅

One Coder chat per email action (reply, compose, summarize, etc.).
Dynamic tools provide thread context on demand, so the model doesn't
need a persistent chat. Label each chat with the Gmail thread ID for
audit/retrieval.

### 3. Where Email Content Lives

```
Email data flow:
  Gmail API → macOS app (local memory) → Coder Chats API (via dynamic tools)
                                              │
                                              ▼
                                         Your Coder instance
                                         (your infra, your control)
```

Email content is sent to Coder only when the user explicitly invokes an AI action. It's passed through the chat message content or tool results — not stored separately. If Coder's chat retention is set to 7 days, the email excerpts in chat history also expire.

**Privacy controls the app should expose:**
- Strip signatures/footers before sending to AI
- Redact phone numbers/addresses (configurable)
- Option to not send quoted reply chains
- Clear indicator of what's being sent to the AI

### 4. macOS Tech Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| **UI Framework** | SwiftUI + AppKit | Native macOS feel, split views, toolbars |
| **Email Rendering** | WKWebView | HTML emails need a web view |
| **Rich Text Editor** | NSTextView or custom | Compose pane with formatting |
| **Networking** | URLSession + Starscream (WS) | Gmail REST + Coder WebSocket streaming |
| **Local Storage** | SwiftData or Core Data | Email cache, account config |
| **Auth (Gmail)** | ASWebAuthenticationSession | OAuth2 flow |
| **Auth (Coder)** | Session token | `CODER_SESSION_TOKEN` or OAuth |
| **Keychain** | Security.framework | Store tokens securely |

### 5. Coder Authentication: OAuth2 Provider ✅

Coder supports acting as an OAuth2 authorization server (experimental,
requires `--experiments oauth2`). This gives us a proper native auth flow:

```
App opens ASWebAuthenticationSession to:
  https://coder.example.com/oauth2/authorize?
    client_id=codermail-macos&
    response_type=code&
    code_challenge=$CODE_CHALLENGE&
    code_challenge_method=S256&
    redirect_uri=codermail://callback

User authenticates in browser → redirected back to app with auth code.
App exchanges code for access token (with PKCE code_verifier).
Token stored in Keychain. Refresh token handles expiry.
```

Key details from `docs/admin/integrations/oauth2-provider.md`:
- PKCE is **required** (good — no client secret in native app)
- Native callback URIs supported (`myapp://callback`)
- Refresh token flow supported
- Discovery endpoint at `/.well-known/oauth-authorization-server`
- Requires admin to register the app and enable `oauth2` experiment

**Fallback**: Session token paste for Coder instances without the
oauth2 experiment enabled. Store in Keychain either way.

---

## Dynamic Tools Design (Detail)

This is the most architecturally interesting part. The LLM on the Coder backend doesn't have direct access to Gmail — the macOS app acts as the bridge.

```swift
// Pseudocode for how dynamic tools would work

let tools: [DynamicTool] = [
    DynamicTool(
        name: "get_email_thread",
        description: "Fetch the full email thread being replied to",
        inputSchema: .object(properties: [
            "thread_id": .string(description: "Gmail thread ID")
        ])
    ),
    DynamicTool(
        name: "get_current_draft",
        description: "Read the current contents of the compose editor",
        inputSchema: .object(properties: [:])
    ),
    DynamicTool(
        name: "update_draft",
        description: "Replace the compose editor contents with new text",
        inputSchema: .object(properties: [
            "body": .string(description: "New email body (HTML or plain text)"),
            "format": .enum(["html", "plain"])
        ])
    ),
    DynamicTool(
        name: "set_subject",
        description: "Set the email subject line",
        inputSchema: .object(properties: [
            "subject": .string(description: "The subject line")
        ])
    ),
    DynamicTool(
        name: "search_emails",
        description: "Search the user's email for relevant context",
        inputSchema: .object(properties: [
            "query": .string(description: "Gmail search query"),
            "max_results": .integer(description: "Max results to return", default: 5)
        ])
    )
]
```

When the model invokes a tool:
1. `StreamChat` delivers an `action_required` event with the tool call
2. The app intercepts it, executes locally (reads from Gmail API, reads from compose field, etc.)
3. App calls `POST /chats/{id}/tool-results` with the result
4. Model continues generating with the new context

This means **the model only ever sees email data that passes through tool calls you control**. You can filter, redact, or truncate before returning results.

---

## What's Missing / Would Need from Coder

### Works today:
- ✅ CreateChat with system prompts
- ✅ Dynamic tools (UnsafeDynamicTools) for client-side execution
- ✅ WebSocket streaming
- ✅ Model selection
- ✅ Chat labels for organization
- ✅ Interrupt/edit flows
- ✅ File upload (for attachments as context)

### Confirmed working:
- **Workspace-less chats** — `CreateChatRequest.WorkspaceID` is optional
  (`*uuid.UUID`). When nil, the handler skips workspace setup entirely.
  The chat runs in the control plane — no workspace spin-up. Perfect for
  lightweight email tasks like drafting and subject line generation.

### Would be nice:
- **Token-level streaming over SSE** — WebSocket works but SSE is
  simpler for HTTP-only clients. Filed in `agents-feedback.md`.
- **Stateless/ephemeral chats** — for one-shot tasks like subject line
  generation, a fire-and-forget mode that auto-deletes after completion.
- **Prompt templates** — server-side prompt templates so the app doesn't
  hardcode system prompts. Admin could tune email-specific prompts
  deployment-wide.

---

## MVP Scope

### Phase 1: Read-only + Reply Assist
- Gmail OAuth2 login
- Inbox/thread view (read-only, no compose from scratch)
- Coder connection setup (URL + session token)
- "Help me reply" button on any email
- Split view: thread on left, AI compose on right
- Stream draft via Coder Chats API
- Iterative refinement ("shorter", "more formal", etc.)
- Copy to clipboard or send via Gmail API

### Phase 2: Full Compose + Inline AI
- Full compose from scratch
- Inline AI suggestions (select text → adjust)
- Subject line generation
- Thread summarization
- Keyboard shortcuts for AI actions

### Phase 3: Power Features
- Multi-account support
- Contact-aware context (past correspondence)
- Smart follow-up reminders ("you haven't replied to X")
- Template system (common reply patterns)
- Unified inbox (multiple Gmail accounts)

---

## Open Questions

1. **Should this be a standalone app or a Safari/Chrome extension?**
   - Native app: better UX, split views, offline, keyboard shortcuts
   - Extension: lower friction, rides on Gmail's UI
   - Leaning native app — the whole point is escaping Gmail's UI and its bad AI

2. **How to handle the chat lifecycle for email tasks?**
   - Create a new chat per "AI action" and archive when done?
   - Keep a background chat per email thread for accumulated context?

3. **Is `UnsafeDynamicTools` stable enough to build on?**
   - Name literally says "unsafe" and "experimental"
   - What's the deprecation/change risk?
   - Could MCP servers be a more stable alternative?

4. **Should the app support non-Gmail (Outlook, IMAP)?**
   - Broader market but 3x the integration surface
   - Could abstract the email provider behind a protocol

5. **Distribution?**
   - Mac App Store (sandboxing constraints, Apple review)
   - Direct download / Homebrew (more freedom, less trust)
   - Open source? (aligns with Coder's ethos)
