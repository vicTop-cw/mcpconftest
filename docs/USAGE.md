# mcpconftest Usage Guide

Complete usage documentation with real output examples.

## Installation

```bash
# From mooncakes.io (MoonBit community package registry)
moon add vicTop-cw/mcpconftest
```

## Quick start

```bash
# Run against built-in fixture (no external server needed)
moon run cmd -- run
```

Output:
```
probing fixture server
[fixture] 20/32 pass, 8 fail
report written: ./mcpconftest-report/report.{json,md,html}
mcpconftest: ALL GREEN (fixture)
```

## CLI reference

### `run` — Probe an MCP server

```bash
moon run cmd -- run [options]
```

Options:
- `--server <cmd>` — MCP server command (repeatable, probed in parallel)
- `--report <dir>` — Report output directory (default `./mcpconftest-report`, `""` disables)
- `--junit` — Also write JUnit XML report

### `list-checks` — List available check categories

```bash
moon run cmd -- list-checks
```

### `version` — Print version

```bash
moon run cmd -- version
```

## Probe your own server

### stdio transport (default)

```bash
# Single server
moon run cmd -- run --server "node my-mcp-server.js"

# Multiple servers in parallel
moon run cmd -- run --server "node server-A.js" --server "python server-B.py"
```

### WebSocket transport

```bash
moon run cmd -- run --server "ws://localhost:3000/mcp"
```

## Report output

Every run writes to the report directory (default `./mcpconftest-report/`):

| File | Format | Purpose |
|---|---|---|
| `report.json` | JSON | Machine-readable CI artifact |
| `report.md` | Markdown | Human-readable summary |
| `report.html` | HTML | Standalone styled page |
| `report-junit.xml` | JUnit XML | CI-native test results (only with `--junit`) |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | All checks pass (or only skips) |
| 1 | At least one check failed |
| 2 | CLI error (unknown subcommand, etc.) |

## Understanding results

### Severity levels

- ✅ **Pass** — Check passed
- ❌ **Fail** — Check failed (spec violation)
- ⏭️ **Skip** — Server doesn't support this capability (not a violation)
- ⚠️ **Warn** — Potential issue (non-critical)

### Sample report output

```markdown
# mcpconftest report
Server: `node my-mcp-server.js`
Protocol: 2026-07-28

## Summary
| Metric | Count |
|---|---|
| Pass | 28 |
| Fail | 2 |
| Skip | 2 |
| Warn | 0 |
| Total timing | 234ms |
| Avg per check | 7ms |

## Details
### ✅ init.jsonrpc (45ms)
jsonrpc=2.0

### ✅ init.server_info (45ms)
serverInfo present

### ❌ tools_list.description (12ms)
tool missing description
{"name":"legacy_tool"}

### ⏭️ logging.unsupported (0ms)
server does not support logging
```

## CI integration

### GitHub Actions / GitCode Actions

See `.github/workflows/ci.yml` and `.gitcode/workflows/ci.yml` for ready-to-use CI templates.

### CI gate script

```bash
bash scripts/ci.sh
```

Runs three gates:
1. `moon check` — Static analysis
2. `moon test` — Unit tests
3. e2e fixture regression — Full probe against built-in fixture

## Check categories

| # | Category | Checks |
|---|---|---|
| 1 | initialize | jsonrpc, server_info, protocol_version, notifications_initialized |
| 2 | capabilities | tools capability declared |
| 3 | tools/list | name + description mandatory |
| 4 | tools/call | error path (-32601 for unknown tool) |
| 5 | notifications | session liveness after unknown notifications |
| 6 | idempotency | repeated identical requests |
| 7 | resources/list, resources/read | resource schema + error path |
| 8 | prompts/list | prompt schema (name mandatory) |
| 9 | ping, keepalive | spec-mandated ping + session stability |
| 10 | protocol negotiation | version matrix (4 protocols) |
| 11 | logging/setLevel | logging capability |
| 12 | completion/complete | prompt completion |
| 13 | resources/subscribe | subscription capability |
| 14 | sampling/createMessage | sampling capability |

## Performance benchmark

Each check reports individual `timing_ms`. Summary includes `total_timing_ms` and `avg_per_check_ms`.

Example:
```
| Total timing | 234ms |
| Avg per check | 7ms |
```

## Multi-server parallel probe

```bash
moon run cmd -- run --server "mcp-server-A" --server "mcp-server-B" --report ./report --junit
```

All servers probed in parallel via `@async.all`. Aggregated report written once.

## Transport support

| Transport | Syntax | Use case |
|---|---|---|
| stdio | `--server "node server.js"` | Local MCP servers |
| WebSocket | `--server "ws://host:port/path"` | Remote MCP servers |

## Troubleshooting

### "read failed" or "timeout"
- Server may not be responding within the default timeout (5000ms)
- Check that the server command is correct and executable

### "spawn failed"
- Command not found in PATH
- Use absolute path: `--server "/usr/local/bin/node server.js"`

### All checks skip
- Server may not be responding to initialize
- Verify server speaks JSON-RPC 2.0 over stdio
