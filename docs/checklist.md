# mcpconftest — MCP Protocol Conformance Checklist

Based on MCP protocol spec `2026-07-28` and JSON-RPC 2.0.

## Category 1 — Initialize Handshake

- [ ] Response includes `jsonrpc: "2.0"`
- [ ] Response includes `result.serverInfo` (name + version)
- [ ] Response includes `result.protocolVersion` matching requested version
- [ ] Response includes `result.capabilities` (may be empty object)
- [ ] Server accepts `notifications/initialized` after handshake
- [ ] Server rejects malformed `initialize` params with error code

## Category 2 — Capabilities

- [ ] `tools` capability declared iff server has tools
- [ ] `resources` capability declared iff server has resources
- [ ] `prompts` capability declared iff server has prompts
- [ ] Undeclared capability is not required to work (graceful degradation)

## Category 3 — tools/list

- [ ] Response `result.tools` is an Array
- [ ] Each tool has `name` (String)
- [ ] Each tool has `description` (String)
- [ ] Each tool has `inputSchema` (Object, optional but recommended)
- [ ] Empty tools list is valid (server with no tools)

## Category 4 — tools/call

- [ ] Valid call returns `result.content` Array
- [ ] Call to non-existent tool returns error with code `-32601` (Method not found)
- [ ] Call with invalid params returns error with code `-32602` (Invalid params)
- [ ] Server does not crash on malformed arguments

## Category 5 — Notifications

- [ ] Unknown notification does not crash server
- [ ] Server remains alive and responsive after unknown notification
- [ ] Server responds to valid request after receiving unknown notification
- [ ] `notifications/initialized` is accepted (no response expected)

## Category 6 — Idempotency

- [ ] Repeated `tools/list` returns identical results
- [ ] Multiple `initialize` calls are rejected (or idempotent per spec)
- [ ] Server handles concurrent requests without state corruption

## Category 7 — JSON-RPC 2.0 Compliance

- [ ] Response `id` matches request `id`
- [ ] Error object has `code` (Int) and `message` (String)
- [ ] Batch requests are handled (if supported)
- [ ] Malformed JSON is rejected with parse error `-32700`

## Category 8 — Robustness

- [ ] Server does not crash on empty request
- [ ] Server does not crash on oversized payload
- [ ] Timeout does not leave zombie process
- [ ] Graceful shutdown via `close` cleans up resources

---

## Current Implementation Status (v0.1)

| Category | Status |
|----------|--------|
| 1. Initialize | ✅ Implemented |
| 2. Capabilities | ✅ Implemented |
| 3. tools/list | ✅ Implemented |
| 4. tools/call | ✅ Implemented |
| 5. Notifications | ✅ Implemented |
| 6. Idempotency | ✅ Implemented |
| 7. JSON-RPC 2.0 | ⏳ Stub (needs real transport) |
| 8. Robustness | ⏳ Stub (needs real transport) |

> v0.1 uses stub transport (Session returns canned responses). Real stdio
> child-process spawning planned for v0.2.
