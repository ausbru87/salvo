# Coder Agents API Feedback

Feedback gathered while designing a macOS Gmail client that uses the Coder
Chats API as its AI backend.

---

## Token-level streaming over SSE

**Current state**: Chat streaming uses WebSocket (`/api/experimental/chats/{id}/stream`).

**Request**: Add an SSE (Server-Sent Events) alternative for the same stream.

**Why**:
- SSE is simpler for HTTP-only clients. No WebSocket library needed — just
  a standard HTTP connection with `Accept: text/event-stream`.
- Native macOS `URLSession` handles SSE natively via `URLSession.bytes`.
  WebSocket requires `URLSessionWebSocketTask` which has a different
  connection lifecycle and error-handling model.
- SSE plays nicer with HTTP proxies, load balancers, and CDNs that may not
  support WebSocket upgrade.
- For clients that only *read* the stream (which is the common case — writes
  go through `POST /messages` and `POST /tool-results`), SSE is a
  better fit than a bidirectional WebSocket.
- Many LLM API clients (OpenAI SDK, Anthropic SDK) already use SSE for
  streaming. A Coder SSE endpoint would feel familiar to developers
  integrating against the API.

**Proposed endpoint**: `GET /api/experimental/chats/{id}/stream/sse`
- Same `ChatStreamEvent` JSON payloads as the WebSocket stream.
- `event:` field maps to `ChatStreamEventType` (message_part, message,
  status, error, queue_update, retry, action_required).
- `data:` field carries the JSON-serialized event.
- Supports `?after_id=N` for resumption, same as WebSocket variant.

**Workaround today**: Clients can use the WebSocket stream. It works fine,
just adds unnecessary complexity for read-only consumers.
