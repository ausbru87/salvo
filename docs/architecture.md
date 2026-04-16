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
┌──────────────────────────────────────────────────────────────┐
│                    Salvo (macOS native)                      │
│                    SwiftUI + AppKit                          │
│                                                              │
│  ┌─────────────────────┐    ┌──────────────────────────────┐ │
│  │     Email View      │    │       AI Compose Pane        │ │
│  │  ContentView.swift  │    │     AIAssistPane.swift       │ │
│  │                     │    │                              │ │
│  │  • Inbox / Labels   │◄──►│  • Reply assist              │ │
│  │  • Thread list      │    │  • Draft refinement          │ │
│  │  • Thread detail    │    │  • Subject lines             │ │
│  │  • Message render   │    │  • Tone rewrite              │ │
│  └──────────┬──────────┘    └──────────────┬───────────────┘ │
│             │         AppState (Observable) │               │
│  ┌──────────▼──────────┐    ┌──────────────▼───────────────┐ │
│  │    GmailAPI module  │    │       CoderAPI module        │ │
│  │                     │    │                              │ │
│  │  GmailClient        │    │  CoderClient (protocol)      │ │
│  │  HTTPGmailClient ───┤    │  HTTPCoderClient ────────────┤ │
│  │  GmailTokenStore    │    │  CoderStreamMessage          │ │
│  │  GmailOAuth         │    │  HTTPHelpers                 │ │
│  │  MessageParser      │    │  CoderOAuth                  │ │
│  └──────────┬──────────┘    └──────────────┬───────────────┘ │
└─────────────┼─────────────────────────────┼─────────────────┘
              │                             │
   HTTPS · OAuth2 Bearer          HTTPS · POST (create, message, tools)
   401 → auto token refresh       WSS   · receive (stream events)
   googleapis.com                 /api/experimental/chats/*
              │                             │
              ▼                             ▼
   ┌─────────────────┐           ┌────────────────────────┐
   │  Gmail REST API │           │   Coder Chats API      │
   │  (email CRUD)   │           │   (AI inference only)  │
   └─────────────────┘           └────────────┬───────────┘
                                              │
                                   ┌──────────▼──────────┐
                                   │  Your Coder Deploy  │
                                   │  Claude / GPT /     │
                                   │  any configured     │
                                   │  model              │
                                   └─────────────────────┘
```

**Key principle**: Gmail API handles email transport and storage. Coder Chats API handles all AI inference. They never cross. Email content reaches Coder only via explicit tool call results — not as a bulk upload.

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
User clicks "Reply"
    │
    ▼
AIEmailService.startReplyAssist(instruction:thread:organizationID:)
    │
    ├─ POST /api/experimental/chats
    │     body: { organization_id, system_prompt, dynamic_tools: [
    │               get_email_thread, get_current_draft,
    │               update_draft, set_subject, search_emails ] }
    │     → Chat { id: UUID }
    │
    ├─ POST /api/experimental/chats/{id}/messages
    │     body: { content: "decline politely" }
    │
    └─ WSS /api/experimental/chats/{id}/stream  ←─ open WebSocket
           │
           │  StreamMessage frames (JSON):
           ├─ { type: "status_change", status: "streaming" }
           ├─ { type: "message_part", part: { type: "tool_call",
           │     tool_call_id: "tc_1", tool_name: "get_email_thread",
           │     args: { thread_id: "abc123" } } }
           │
           └─ status_change: action_required
                  │
                  ▼
         EmailToolExecutor.execute("get_email_thread", args)
                  │
                  ├─ GmailClient.getThread(id: "abc123", format: .full)
                  │     GET googleapis.com/gmail/v1/users/me/threads/abc123
                  │     → GmailThread (messages, headers, bodies)
                  │
                  └─ MessageParser.extractBody / extractSender (local)
                         │
                         ▼
         POST /api/experimental/chats/{id}/tool-results
               body: { tool_results: [{ tool_call_id: "tc_1",
                         output: { thread_id, messages: [...] } }] }
                         │
                         ▼
         WSS /api/experimental/chats/{id}/stream  ←─ new stream
               │
               ├─ { type: "message_part", part: { type: "text",
               │     content: "Hi Sarah,\n\nThanks for…" } }   (×N tokens)
               └─ { type: "status_change", status: "complete" }
                         │
                         ▼
         AIEmailService.currentDraft ← accumulated text
         AIAssistPane renders streamed draft in real time

User types "make the second paragraph less formal"
    │
    ▼
AIEmailService.refineCurrentDraft(instruction:)
    │
    ├─ POST /api/experimental/chats/{id}/messages
    │     body: { content: "make the second paragraph less formal" }
    │
    └─ WSS  →  model calls get_current_draft  →  submitToolResults
           →  streams updated draft

User satisfied → Send button
    │
    ▼
Gmail REST API  (send not yet wired — Phase 1 scope)

Session ends:
    └─ AIEmailService.finishSession()
           └─ DELETE /api/experimental/chats/{id}
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

| Component | Technology | Status |
|-----------|-----------|--------|
| **UI Framework** | SwiftUI + AppKit | ✅ Implemented |
| **Email Rendering** | WKWebView | Planned (Phase 2) |
| **Rich Text Editor** | NSTextView or custom | Planned (Phase 2) |
| **Gmail HTTP** | `URLSession` (REST) | ✅ `HTTPGmailClient` |
| **Coder HTTP** | `URLSession` | ✅ `HTTPCoderClient` |
| **Coder WebSocket** | `URLSessionWebSocketTask` | ✅ `openStream()` in `HTTPCoderClient` |
| **Gmail Auth** | `ASWebAuthenticationSession` + `GmailOAuth` | ✅ OAuth2 + token refresh |
| **Coder Auth** | Session token or OAuth2 PKCE | ✅ `CoderOAuth` + `Coder-Session-Token` header |
| **Token Storage** | `Security.framework` Keychain | ✅ `AccountManager` |
| **Local Cache** | SwiftData or Core Data | Planned (Phase 2) |

### 5. Coder Authentication: OAuth2 Provider ✅

Coder supports acting as an OAuth2 authorization server (experimental,
requires `--experiments oauth2`). This gives us a proper native auth flow:

```
App opens ASWebAuthenticationSession to:
  https://coder.example.com/oauth2/authorize?
    client_id=salvo-macos&
    response_type=code&
    code_challenge=$CODE_CHALLENGE&
    code_challenge_method=S256&
    redirect_uri=salvo://callback

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

## Networking Layer

### CoderAPI module

```
CoderClient (protocol)
    │
    └── HTTPCoderClient (struct)
            │
            ├── HTTPHelpers (extension)
            │     ├── static encoder  JSONEncoder  .convertToSnakeCase
            │     ├── static decoder  JSONDecoder  .convertFromSnakeCase + .iso8601
            │     ├── applyAuth()     Coder-Session-Token  or  Authorization: Bearer
            │     ├── makeRequest()   path + method + optional Encodable body
            │     ├── execute()       URLSession.data() → validate status → Data
            │     └── mapHTTPError()  401→unauthorized  403→forbidden  404→notFound
            │                        409→conflict  429→usageLimitExceeded  5xx→serverError
            │
            ├── openStream(chatID:) → AsyncThrowingStream<ChatStreamEvent, Error>
            │     │
            │     ├── makeWebSocketURL()  https→wss  /  http→ws  (URLComponents swap)
            │     ├── URLSessionWebSocketTask.resume()
            │     └── recursive receive() callback loop
            │               │
            │               ▼
            │         CoderStreamMessage (Decodable)
            │               │  JSON frame { type, part | status | message }
            │               ▼
            │         ChatStreamEvent
            │           .messagePart(ChatMessagePart)   text or tool_call chunks
            │           .statusChange(ChatStatus)        streaming/idle/actionRequired/complete
            │           .error(String)
            │           .done                            → task.cancel + continuation.finish
            │
            └── Endpoints
                  POST  /api/experimental/chats                        createChat
                  POST  /api/experimental/chats/{id}/messages          streamChat (then WSS)
                  POST  /api/experimental/chats/{id}/tool-results      submitToolResults (then WSS)
                  DELETE /api/experimental/chats/{id}                  archiveChat
                  GET   /api/experimental/chats/models?organization_id listModels
                  WSS   /api/experimental/chats/{id}/stream            openStream
```

### GmailAPI module

```
GmailClient (protocol)
    │
    └── HTTPGmailClient (struct)
            │
            ├── GmailTokenStore (actor)   ← serializes token mutation
            │     var  accessToken  (refreshed on 401)
            │     let  refreshToken
            │     let  clientID
            │
            ├── makeRequest(path:queryItems:)
            │     awaits tokenStore.accessToken → Authorization: Bearer
            │
            ├── execute(_:)
            │     → 200–299: return Data
            │     → 401:     GmailOAuth.refreshAccessToken() → retry once
            │     → 404:     .notFound
            │     → 429:     .rateLimited(retryAfter: Retry-After header)
            │     → 5xx:     .serverError(statusCode:)
            │
            ├── static decoder  JSONDecoder  .convertFromSnakeCase
            │
            └── Endpoints
                  GET  /profile                    getProfile
                  GET  /messages?q=&maxResults=    listMessages
                  GET  /messages/{id}?format=      getMessage
                  GET  /threads/{id}?format=       getThread
                  GET  /labels                     listLabels
```

---

## Dynamic Tools Design (Detail)

The LLM on Coder has no direct Gmail access — the macOS app is the bridge. Five tools are registered with every chat session and executed locally by `EmailToolExecutor`:

| Tool | Args | Local execution | Output to model |
|------|------|-----------------|-----------------|
| `get_email_thread` | `thread_id: String` | `GmailClient.getThread(.full)` + `MessageParser` | Thread with messages: from, to, date, subject, body |
| `get_current_draft` | _(none)_ | Read `AIEmailService.currentDraft` | `{ body, subject }` |
| `update_draft` | `body: String` | Write `AIEmailService.currentDraft` | `{ status: "ok" }` |
| `set_subject` | `subject: String` | Write `AIEmailService.currentSubject` | `{ status: "ok" }` |
| `search_emails` | `query: String`, `max_results?: Int` | `GmailClient.listMessages()` + `getMessage(.minimal)` ×N | `{ results: [{ id, thread_id, snippet }] }` |

When the model invokes a tool, the stream delivers `statusChange(.actionRequired)`. `AIEmailService` intercepts this, calls `EmailToolExecutor.execute()`, then calls `submitToolResults()` which opens a new WebSocket stream for the continuation. The model never sees raw Gmail data — only what the tool executor chooses to return.

This means **you can filter, redact, or truncate** before returning results: strip signatures, redact phone numbers, omit quoted chains.

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
