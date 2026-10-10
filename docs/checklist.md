# mcpconftest — MCP Protocol Conformance Checklist

Based on MCP protocol spec `2026-07-28` and JSON-RPC 2.0.

## Category 1 — Initialize Handshake

- [x] Response includes `jsonrpc: "2.0"`
- [x] Response includes `result.serverInfo` (name + version)
- [x] Response includes `result.protocolVersion` matching requested version
- [x] Response includes `result.capabilities` (may be empty object)
- [x] Server accepts `notifications/initialized` after handshake
- [x] Server rejects unsupported protocol versions with error `-32600`

## Category 2 — Capabilities

- [x] `tools` capability declared when tools are present
- [x] `resources` capability declared when resources are present
- [x] `prompts` capability declared when prompts are present
- [x] Undeclared capability is not required to work (graceful skip)

## Category 3 — tools/list

- [x] Response `result.tools` is an Array
- [x] Each tool has `name` (String)
- [x] Each tool has `description` (String)
- [x] Each tool has `inputSchema` (Object, optional but recommended)
- [x] Empty tools list is valid

## Category 4 — tools/call

- [x] Valid call returns `result.content` Array
- [x] Call to non-existent tool returns error with code `-32601` (Method not found)
- [x] Call with invalid params returns error with code `-32602` (Invalid params)

## Category 5 — Notifications

- [x] Unknown notification does not crash server
- [x] Server remains alive and responsive after unknown notification
- [x] Server responds to valid request after receiving unknown notification
- [x] `notifications/initialized` is accepted (no response expected)

## Category 6 — Idempotency

- [x] Repeated `tools/list` returns identical results
- [x] Repeated `resources/list` returns identical results
- [x] Repeated `prompts/list` returns identical results

## Category 7 — Resources

- [x] `resources/list` returns resources with `uri` + `name`
- [x] `resources/read` on non-existent resource returns error `-32600`
- [x] `resources/subscribe` supported or gracefully skipped

## Category 8 — Prompts

- [x] `prompts/list` returns prompts with `name`
- [x] `completion/complete` supported or gracefully skipped

## Category 9 — Ping & Keepalive

- [x] Server responds to `ping` with empty result (spec-mandated)
- [x] Server survives 3 consecutive pings (keepalive)

## Category 10 — Protocol Negotiation

- [x] Server echoes `2026-07-28` when requested
- [x] Server echoes `2025-06-18` when requested
- [x] Server echoes `2025-03-26` when requested
- [x] Server rejects `1999-01-01` with error `-32600`

## Category 11 — Logging

- [x] `logging/setLevel` supported or gracefully skipped

## Category 12 — Completion

- [x] `completion/complete` returns `completion.values` array or skipped

## Category 13 — Subscription

- [x] `resources/subscribe` supported or gracefully skipped

## Category 14 — Sampling

- [x] `sampling/createMessage` returns `content.text` or skipped

## Category 15 — JSON-RPC 2.0 Deep

- [x] Batch array request returns a response array
- [x] Batch response item count matches request count
- [x] Every batch response item id matches the request id exactly
- [x] Batch error items carry a valid error object
- [x] Number ids (1, 42) echoed back with matching type + value
- [x] String ids (`req-1`, special chars) echoed back with matching type + value
- [x] `error.code` is an integer in `-32768..-32000` (reserved range)
- [x] `error.message` is a non-empty string
- [x] `error.data` is optional
- [x] `result` and `error` are mutually exclusive in one response
- [x] Error response carries `jsonrpc: "2.0"`

---

## Implementation Status (v0.6)

| Category | Status |
|----------|--------|
| 1. Initialize | ✅ Implemented |
| 2. Capabilities | ✅ Implemented |
| 3. tools/list | ✅ Implemented |
| 4. tools/call | ✅ Implemented |
| 5. Notifications | ✅ Implemented |
| 6. Idempotency | ✅ Implemented |
| 7. Resources | ✅ Implemented |
| 8. Prompts | ✅ Implemented |
| 9. Ping & Keepalive | ✅ Implemented |
| 10. Protocol Negotiation | ✅ Implemented |
| 11. Logging | ✅ Implemented |
| 12. Completion | ✅ Implemented |
| 13. Subscription | ✅ Implemented |
| 14. Sampling | ✅ Implemented |
| 15. JSON-RPC 2.0 Deep | ✅ Implemented |

All 15 categories implemented with real stdio + WebSocket transport.
