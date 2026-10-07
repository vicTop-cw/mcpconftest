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

## Quick start

```bash
# Build
moon build

# Run against a local MCP server
moon run cmd/cli/main -- run --server "path/to/your-mcp-server"

# With report output + CI gate
moon run cmd/cli/main -- run --server "..." --report ./report --ci
```

## Project layout

```
src/lib/
  types.mbt       — CheckResult / Report types + constructors
  types_test.mbt  — in-package unit tests
  session.mbt     — stdio JSON-RPC session driver
  checks.mbt      — six conformance check categories
  report.mbt      — report rendering (JSON / Markdown) + build_report
cmd/cli/main.mbt  — CLI entry point
cmd/main.mbt      — demo entry point
```

## Why MoonBit?

- The MoonBit ecosystem has an MCP *SDK* (`colmugx/mcp`) but **no conformance suite** — a gap this project fills.
- MoonBit's `js+native` target means one codebase runs natively and in browsers.
- The spec is small enough that a single-pass conformance probe fits in a few hundred lines.

## License

Apache-2.0
