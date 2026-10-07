# mcpconftest report

Server: `node tests/demo/compliant_server.js`

Protocol: 2026-07-28

Timestamp: 2026-10-07T13:37:59.763Z

## Summary

| Metric | Count |
|---|---|
| Pass | 24 |
| Fail | 1 |
| Skip | 2 |
| Warn | 0 |
| Total timing | 125ms |
| Avg per check | 4ms |

## Details

### ✅ init.jsonrpc (66ms)

jsonrpc=2.0

### ✅ init.server_info (66ms)

serverInfo present

### ✅ init.protocol_version (66ms)

version=2026-07-28

### ✅ init.notifications_initialized (66ms)

sent OK

### ✅ caps.tools (1ms)

tools capability declared

### ✅ tools_list.name (2ms)

tool has name

### ✅ tools_list.description (2ms)

tool has description

### ✅ tools_list.name (2ms)

tool has name

### ✅ tools_list.description (2ms)

tool has description

### ✅ tools_call.error (1ms)

non-existent tool returned correct error code -32601

### ✅ notifications.unknown (1ms)

unknown notification sent without crash

### ✅ notifications.alive (1ms)

session still alive after unknown notification

### ✅ idempotency (2ms)

repeated tools/list returned same result

### ✅ resources_list.uri (1ms)

resource has uri

### ✅ resources_list.name (1ms)

resource has name

### ✅ prompts_list.name (1ms)

prompt has name

### ❌ resources_read.no_error (0ms)

expected error for non-existent resource

```json
{"jsonrpc":"2.0","id":10,"result":{"contents":[{"uri":"file:///__mcpconftest_nonexistent__","text":"Hello from demo resource"}]}}
```

### ✅ ping.responds (0ms)

ping answered with result

### ✅ keepalive.stable (2ms)

3/3 keepalive pings succeeded

### ✅ negotiation.2026-07-28 (2ms)

server echoed 2026-07-28

### ✅ negotiation.2025-06-18 (2ms)

server echoed 2025-06-18

### ✅ negotiation.2025-03-26 (2ms)

server echoed 2025-03-26

### ✅ negotiation.1999-01-01.rejected (2ms)

unsupported version rejected with error (compliant)

### ✅ logging.set_level (1ms)

logging/setLevel accepted

### ✅ completion.values (0ms)

completion returned values array

### ⏭️ subscribe.unsupported (1ms)

server does not support subscribe

### ⏭️ sampling.unsupported (1ms)

server does not support sampling

