# mcpconftest

MCP protocol conformance probe — checks any MCP server (stdio or WebSocket) against the spec.

## Usage

```bash
# Run against built-in fixture (default)
moon run cmd -- run

# Probe one or more servers in parallel
moon run cmd -- run --server "node my-mcp-server.js" --server "python server.py"

# Probe a WebSocket MCP server
moon run cmd -- run --server "ws://localhost:3000/mcp"

# Write reports to custom directory (default ./mcpconftest-report, "" disables)
moon run cmd -- run --server "node server.js" --report ./my-report

# Include JUnit XML output
moon run cmd -- run --junit

# List available check categories
moon run cmd -- list-checks

# Print version
moon run cmd -- version
```

Output: JSON + Markdown + HTML reports + optional JUnit XML + CI gate (exit code 0 = pass, 1 = any fail).

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

Each check reports individual `timing_ms`. Summary includes `total_timing_ms` and `avg_timing_ms` across all checks.

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
