# mcpconftest

**Pure MoonBit MCP protocol conformance test suite + CLI** — probe any stdio MCP server against the `2026-07-28` protocol spec.

## What it does

`mcpconftest` spawns a target MCP server as a child process, speaks JSON-RPC over stdio, and runs a battery of conformance checks:

| # | Check category | What it verifies |
|---|---|---|
| 1 | **Initialize handshake** | `jsonrpc: "2.0"`, `serverInfo`, `protocolVersion` match |
| 2 | **Capabilities** | `tools` capability declared when tools are present |
| 3 | **tools/list schema** | Every tool has `name` + `description` |
| 4 | **tools/call error path** | Non-existent tool returns proper JSON-RPC error code |
| 5 | **Notifications** | Unknown notifications don't crash the server |
| 6 | **Idempotency** | Repeated `tools/list` returns stable results |

Output: JSON report + optional Markdown summary + CI gate (exit code 0 = pass, 1 = any fail).

## Reports (v0.4)

Every run writes to the report directory:
- `report.json` — machine-readable CI artifact (per-check results + summary counts)
- `report.md` — human-readable summary table + details
- `report.html` — standalone styled page (collapsible per-check details)
- `report-junit.xml` — JUnit XML, only with `--junit` (CI-native test results)

Report writing is an observation surface — it never changes the exit verdict.

## Quick start

```bash
# E2E against the built-in partially-compliant fixture (strict expectations)
moon run cmd/e2e

# Probe an arbitrary MCP server
moon run cmd/e2e -- --server "node path/to/your-mcp-server.js serve"

# CI gate (moon check + moon test + e2e fixture, all must pass)
bash scripts/ci.sh

# Reports land in ./mcpconftest-report/ (report.json + report.md)
# Customize: moon run cmd/e2e -- --report ./my-report   ("" disables)
```

## Project layout

```
src/lib/
  types.mbt       — CheckResult / Report types + constructors
  types_test.mbt  — in-package unit tests
  session.mbt     — real stdio JSON-RPC session driver (child_process.spawn + async FFI)
  checks.mbt      — six conformance check categories
  report.mbt      — report rendering (JSON / Markdown) + build_report
cmd/e2e/main.mbt  — e2e entry: fixture regression + --server probing
tests/fixtures/   — deliberately partially-compliant MCP server (node)
scripts/ci.sh     — CI gate script
docs/
  session-arch.md — transport design notes
  fist-mbt-probe.md — real-server probe findings
```

## Why MoonBit?

- The MoonBit ecosystem has an MCP *SDK* (`colmugx/mcp`) but **no conformance suite** — a gap this project fills.
- MoonBit's `js+native` target means one codebase runs natively and in browsers.
- The spec is small enough that a single-pass conformance probe fits in a few hundred lines.

## License

Apache-2.0
