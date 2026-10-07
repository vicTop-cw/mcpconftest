# mcpconftest

MCP protocol conformance probe — checks any MCP server (stdio or WebSocket) against the spec.

## Quick start

```bash
# 1. Install (from mooncakes.io)
moon add vicTop-cw/mcpconftest

# 2. Run against built-in fixture (no external server needed)
moon run cmd -- run

# 3. Check the report
cat mcpconftest-report/report.md
```

## Demo output

Running against the built-in partially-compliant fixture:

```
$ moon run cmd -- run
probing fixture server
[fixture] 20/32 pass, 8 fail
report written: ./mcpconftest-report/report.{json,md,html}
mcpconftest: ALL GREEN (fixture)
```

Report summary (`report.md`):

```
# mcpconftest report
Server: `fixture`
Protocol: 2026-07-28

## Summary
| Metric | Count |
|---|---|
| Pass | 20 |
| Fail | 8 |
| Skip | 4 |
| Warn | 0 |
| Total timing | 141ms |
| Avg per check | 4ms |
```

Sample findings — fixture deliberately violates spec to prove detection works:

```
### ❌ tools_list.description
tool missing description
{"name":"no_desc_tool"}

### ❌ tools_call.error_code
expected -32601, got -32000 (wrong error code for unknown tool)

### ❌ ping.responds
ping returned -32601 (spec: server MUST respond to ping)

### ❌ keepalive.no_result_1
keepalive ping 1 failed

### ⏭️ logging.unsupported
server does not support logging
```

Exit code: `0` (ALL GREEN) — fixture is *expected* to have failures; the probe correctly detects them. Run your own server to verify real conformance.

## Usage

```bash
# Probe your own MCP server (stdio)
moon run cmd -- run --server "node my-mcp-server.js"

# Probe multiple servers in parallel
moon run cmd -- run --server "mcp-server-A" --server "mcp-server-B"

# Probe a WebSocket MCP server
moon run cmd -- run --server "ws://localhost:3000/mcp"

# Custom report directory (default ./mcpconftest-report, "" disables)
moon run cmd -- run --server "node server.js" --report ./my-report

# Include JUnit XML (CI-native)
moon run cmd -- run --junit

# List check categories
moon run cmd -- list-checks

# Print version
moon run cmd -- version
```

## Reports

Every run writes to the report directory:
- `report.json` — machine-readable CI artifact (per-check results + summary + timing)
- `report.md` — human-readable summary + details + per-check timing
- `report.html` — standalone styled page (collapsible details)
- `report-junit.xml` — JUnit XML, only with `--junit` (CI-native)

## Check categories (v0.6)

- **initialize** — jsonrpc, server_info, protocol_version
- **capabilities** — response structure
- **tools/list** — tool schema (name, description mandatory)
- **tools/call** — error path (-32601 for unknown tool)
- **notifications** — session liveness after unknown notifications
- **idempotency** — repeated identical requests
- **resources/list, resources/read** — resource schema + error path
- **prompts/list** — prompt schema (name mandatory)
- **ping, keepalive** — spec-mandated ping + session stability
- **protocol negotiation** — version matrix (4 protocols)
- **logging/setLevel** — logging capability
- **completion/complete** — prompt completion
- **resources/subscribe** — subscription capability
- **sampling/createMessage** — sampling capability

## Transport support

- **stdio** (default) — spawn child process, JSON-RPC over stdin/stdout
- **WebSocket** — connect to `ws://` or `wss://`, JSON-RPC over messages

## Performance benchmark

Each check reports individual `timing_ms`. Summary includes `total_timing_ms` and `avg_per_check_ms` across all checks.

## Multi-server parallel probe

```bash
moon run cmd -- run --server "mcp-server-A" --server "mcp-server-B" --report ./report --junit
```

All servers probed in parallel via `@async.all`. Aggregated report written once.

Report writing is an observation surface — it never changes the exit verdict.

## CI gate

```bash
bash scripts/ci.sh
```

Three gates: `moon check` + `moon test` + e2e fixture regression. All must pass.

## CI integration

- `.github/workflows/ci.yml` — GitHub Actions
- `.gitcode/workflows/ci.yml` — GitCode Actions

## Project layout

```
src/lib/
  types.mbt       — CheckResult / Report types + constructors
  types_test.mbt  — in-package unit tests
  session.mbt     — stdio + WebSocket JSON-RPC session driver
  checks.mbt      — 14 conformance check categories
  report.mbt      — JSON / Markdown / HTML / JUnit rendering
  probe.mbt       — probe orchestration (fixture + target + parallel)
cmd/main.mbt      — CLI entry: run / list-checks / version
tests/fixtures/   — deliberately partially-compliant MCP server (node)
scripts/ci.sh     — CI gate
```

## License

MIT
