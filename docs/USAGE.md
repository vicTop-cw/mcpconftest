# mcpconftest Usage Guide

Complete usage documentation with real output examples.

## Installation

```bash
# 一行命令安装并注册（Windows PowerShell）
iex ((irm https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
#    Linux / WSL
# curl -fsSL https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install.sh | bash

# 本地 / 离线（发布前自证推荐）：见 docs/INSTALL.md（release_zip.ps1 + -LocalZip）
```

开发 / 源码直跑：

```bash
moon add vicTop-cw/mcpconftest   # mooncakes.io 注册表
moon run cmd -- run              # = mcpconftest run
```

## Quick start

```bash
# 安装后直接可用；内建 fixture（无需外部 server）
mcpconftest run --fixture
# 开发态等价
moon run cmd -- run
```

Output:
```
probing fixture server
[fixture] 38/58 pass, 15 fail
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
mcpconftest version
# 开发态：moon run cmd -- version
```

### `serve` — Run as an MCP server

```bash
mcpconftest serve
```

按 2026-07-28 无状态 MCP 协议以 stdio 传输启动，暴露三个工具：
`version`（版本）、`run_probe`（对指定 MCP server 做合规探测，参数 `servers` /
`report_dir` / `junit`）、`list_checks`（检查类别清单）。任何 stdio MCP 客户端
可直接拉起；重复 initialize 按无状态协议返回 -32601。

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
| 15 | batch | JSON-RPC batch request handling |
| 16 | id_matching | JSON-RPC id matching between request and response |
| 17 | error_schema | Error response schema conformance (code/message) |
| 18 | resources_read_error | resources/read error path (-32602 / missing resource) |
| 19 | notifications_initialized | initialized notification handling |

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

## Backends

安装器分发 JS 后端（Node ≥18，推荐 22+）；native 后端源码构建：

```bash
moon build --target native --release
# Windows: _build/native/release/build/cmd/cmd.exe
# Linux:   _build/native/release/build/cmd/cmd
```

`src/lib` 为 `js+native` 双 target；native 下 stdio 探测经 spawn 子进程真实工作，
WebSocket 探测经 `moonbitlang/async/websocket` 真实连接（`ws://` / `wss://`，文本帧
JSON-RPC，超时与关闭语义与 js 后端一致）。

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
