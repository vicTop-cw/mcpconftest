---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_099086bdc6d811f197b3525400248c00
    ReservedCode1: yk7X3aN7JNUaJMtzlgn0iuUpQ9Z34d7yaNugqcUVrMSRoy6XH3RT6SFbUN8CDJDJ+JYXEOdLNm334LgwHUysKyQqmxlSw/zdQPPDnBvXbz3k0Yd5TpmLDgRNsCEbcFCwNhH5BTngZ5j8lKutuhwFWKvQ5fl7lXWQl6YsE3VAg6t88AHCHoI2OJr1rUg=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_099086bdc6d811f197b3525400248c00
    ReservedCode2: yk7X3aN7JNUaJMtzlgn0iuUpQ9Z34d7yaNugqcUVrMSRoy6XH3RT6SFbUN8CDJDJ+JYXEOdLNm334LgwHUysKyQqmxlSw/zdQPPDnBvXbz3k0Yd5TpmLDgRNsCEbcFCwNhH5BTngZ5j8lKutuhwFWKvQ5fl7lXWQl6YsE3VAg6t88AHCHoI2OJr1rUg=
---

# mcpconftest

MCP protocol conformance probe — checks any MCP server (stdio or WebSocket) against the spec.

## Quick start

```bash
# 1. 一行命令安装并注册（Windows PowerShell）
iex ((irm https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
#    Linux / WSL
# curl -fsSL https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install.sh | bash

# 2. 探测内建 fixture（无需外部 server；38/58 pass, 15 fail 为预期违规）
mcpconftest run --fixture

# 3. 查报告
cat mcpconftest-report/report.md

# 4. 以 MCP server 形态启动（stdio，暴露 version / run_probe / list_checks）
mcpconftest serve
```

开发 / 源码直跑：

```bash
moon add vicTop-cw/mcpconftest   # 或直接克隆本仓库
moon run cmd -- run              # = mcpconftest run
moon run cmd -- serve            # = mcpconftest serve
```

详见 [docs/INSTALL.md](docs/INSTALL.md)（一行安装注册全指南）与 [docs/USAGE.md](docs/USAGE.md)。

## Demo output

Running against the built-in partially-compliant fixture:

```
$ moon run cmd -- run
probing fixture server
[fixture] 38/58 pass, 15 fail
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
| Pass | 38 |
| Fail | 15 |
| Skip | 5 |
| Warn | 0 |
| Total timing | 0ms |
| Avg per check | 0ms |
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
# CLI 四子命令（安装后直接 `mcpconftest`；开发态等价 `moon run cmd --`）
mcpconftest version        # mcpconftest v0.9.0
mcpconftest list-checks    # 列出全部检查类别
mcpconftest run --server "node my-mcp-server.js"          # 探测指定 MCP server（stdio）
mcpconftest run --server "mcp-server-A" --server "mcp-server-B"   # 多 server 并行
mcpconftest run --server "ws://localhost:3000/mcp"        # WebSocket 传输
mcpconftest run --server "node server.js" --report ./my-report   # 自定义报告目录
mcpconftest run --server "node server.js" --junit         # 附 JUnit XML
mcpconftest run --fixture                                 # 内建 fixture 自检
mcpconftest serve                                         # MCP server 形态（stdio）
```

## MCP 化（库即 MCP server）

`mcpconftest serve` 以无状态 MCP server（2026-07-28 协议）暴露三个原生工具：
`version` / `run_probe`（参数：servers、report_dir、junit）/ `list_checks`；
并内嵌**自实现 OpsEngine**（src/lib/ops_*.mbt，语义对齐 FIST-Mbt 0.3.6 缓存，
不依赖外部 fist-mbt 包）作为内部工具库，额外注册 `mcpcf.*` 七工具
（`ops_init` / `run_batch` / `verify` / `watchdog` / `report` / `circuit` / `review`），
实现"规约驱动巡检 + 自驱运维"一体化。任何支持 stdio MCP 的客户端可直接拉起
`mcpconftest serve`。

### 自实现 OpsEngine（路线 A）

- 模块：`ops_task.mbt`（Task / TaskStatus 九态 + 状态机）、`ops_store.mbt`
  （OpsMemoryStore / OpsSqliteStore 双后端，SQLite 全部参数化绑定）、
  `ops_engine.mbt`（OpsEngine：publish / verify / circuit / review 等操作）、
  `fist_ops.mbt`（mcpcf.* 七工具接线与数据目录隔离）。
- 数据文件 `mcpconftest-ops.db`，默认 `%LOCALAPPDATA%\mcpconftest\data`，
  `MCPCONFTEST_DATA_DIR` 可覆盖，schema 与 fist-mbt 0.3.6 逐字一致
  （可读旧库；SQLite 打开失败回退内存后端，`backend` 报 `memory://`）。
- 七工具对外签名与数据语义与旧嵌入层完全一致；mcpcf.* 为内部工具，
  不入规格树（IRON-LAWS R3 豁免，见 scripts/verify-specs.ps1）。

## 可验证规约层（sigmaLang 风格）

检查项不再硬编码：以 `specs/`（Markdown + JSON）为单一真源，
引擎在运行时读取规格动态装配 `list-checks`。

- `specs/` — 28 类检查项的机读规格（operations / preconditions / laws / fingerprint sha256）
- `laws/iron-laws.md` — 五条铁律：
  - **L1 规格即真源**：list-checks 必须与 specs 一致（门禁 `scripts/verify-specs.ps1`）
  - **L2 双端共识**：js/native 两后端检查清单输出必须一致（CI 门禁）
  - **L3 有规必有语料**：每个检查项至少一对 pass/fail 负向语料（门禁 `scripts/verify-corpus.ps1`）
  - **L4 无指纹不发布**：spec 缺失 sha256 指纹不得发布
  - **L5 破坏性变更必示警**：变更既有检查语义必须走 `docs/rule-lifecycle.md` 演进流程
- `corpus/` — 每类检查项的 pass / fail 样例语料（负向测试强制）
- `scripts/new-check.ps1` — 新增检查项脚手架，自动生成 spec + 语料模板

新检查项 = 写 spec + 补语料 + 跑门禁，三件套齐活即可合入。

## 双后端

| 后端 | 产物 | 来源 |
|---|---|---|
| JS | `mcpconftest.js`（Node ≥18） | 安装器分发的发行资产（`mcpconftest-js-v<版本>.zip`） |
| native | `cmd.exe` / `cmd` | `moon build --target native --release` |

`src/lib` 配置 `supported_targets = "js+native"`，两后端共享同一 CLI / MCP 逻辑；
native 后端 stdio 探测通过 spawn 子进程真实工作，WebSocket 探测通过
`moonbitlang/async/websocket` 真实连接（`ws://` / `wss://`）。

## Reports

Every run writes to the report directory:
- `report.json` — machine-readable CI artifact (per-check results + summary + timing)
- `report.md` — human-readable summary + details + per-check timing
- `report.html` — standalone styled page (collapsible details)
- `report-junit.xml` — JUnit XML, only with `--junit` (CI-native)

## Check categories (v0.9.0, spec-driven)

28 类检查项由 `specs/` 单一真源驱动（运行时装配 + sha256 指纹）。

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
- **batch** — JSON-RPC batch request handling
- **id_matching** — JSON-RPC id matching between request and response
- **error_schema** — Error response schema conformance (code/message)

### stateless (2026-07-28 无状态核心)

- **server/discover** — 无状态能力发现（supportedVersions / capabilities / serverInfo）
- **version_negotiation** — 版本协商内联化（-32022 + data.supported）
- **self_describing** — 每请求自描述 _meta（protocolVersion / clientInfo / clientCapabilities）
- **missing_capability** — 缺失客户端能力返回 -32021（MissingRequiredClientCapabilityError）
- **list_cache** — 列表结果缓存提示（ttlMs / cacheScope）
- **schema_2020_12** — Tools 完整 JSON Schema 2020-12 合规（oneOf / anyOf / allOf / $ref）
- **resource_error_code** — 资源未找到错误码 -32602（替代旧 -32002）
- **mrtr** — MRTR input_required 往返（resultType / requests / inputResponses）
- **deprecations** — Roots / Sampling / Logging 弃用能力标注

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

Gates: `moon check` + `moon test` + e2e fixture regression（GitHub Actions 另有
`iron-laws` job 执行 L1/L2/L3 铁律门禁）。All must pass.

## CI integration

- `.github/workflows/ci.yml` — GitHub Actions
- `.gitcode/workflows/ci.yml` — GitCode Actions

## Project layout

```
specs/             — 28 类检查项机读规格（单一真源，含 sha256 指纹）
laws/iron-laws.md  — 五条铁律（L1-L5）
corpus/            — 每类检查项 pass/fail 语料（负向测试强制）
src/lib/
  types.mbt       — CheckResult / Report types + constructors
  types_test.mbt  — in-package unit tests
  session.mbt     — stdio + WebSocket JSON-RPC session driver
  session_io_js.mbt   — JS 后端 stdio 抽象实现（inline extern）
  session_io_native.mbt — native 后端实现（spawn 子进程真实 stdio + async/websocket 真实 WS）
  specs.mbt       — 规格驱动装配（list_checks_spec，优先规格回退静态）
  ops_task.mbt    — 自实现 OpsEngine：Task / TaskStatus 九态 + 状态机（对齐 fist-mbt 0.3.6）
  ops_store.mbt   — 自实现 OpsEngine：OpsMemoryStore / OpsSqliteStore 双后端（SQL 参数化）
  ops_engine.mbt  — 自实现 OpsEngine：OpsEngine（publish/verify/circuit/review/now 语义）
  fist_ops.mbt    — 自实现引擎接线：mcpcf.* 七工具 + 数据目录隔离（不依赖外部 fist-mbt 包）
  checks.mbt      — 28 conformance check categories
  report.mbt      — JSON / Markdown / HTML / JUnit rendering
  probe.mbt       — probe orchestration (fixture + target + parallel)
  server.mbt      — MCP server（serve：version / run_probe / list_checks）
  mcp_server.mbt  — MCP server 装配（含 with_mcpcf_tools 注册）
cmd/main.mbt      — CLI entry: run / list-checks / version / serve
tests/fixtures/   — deliberately partially-compliant MCP server (node)
scripts/ci.sh     — CI gate
scripts/gen_apply_pdf_mcpconftest.py — 生成一页《项目申报书》PDF（A4, fpdf2）；用法: `python scripts/gen_apply_pdf_mcpconftest.py [out.pdf]`（依赖: `pip install fpdf2`；自动查找 Windows 中文字体 simhei/msyh/simsun）
scripts/verify-specs.ps1   — L1 门禁（规格 vs list-checks 一致性）
scripts/verify-corpus.ps1  — L3 门禁（语料覆盖 100%）
scripts/new-check.ps1      — 新增检查项脚手架
scripts/blackbox/
  install_onecmd.ps1  — Windows 一行命令安装注册（shim + PATH）
  install.sh          — Linux/WSL 一行命令安装注册
  release_zip.ps1     — Windows 打包 JS 发行资产
  release_zip.sh      — Linux 打包 JS 发行资产
docs/INSTALL.md     — 安装注册全指南
docs/USAGE.md       — 完整用法
docs/rule-lifecycle.md — L5 规则演进流程
docs/fist-data-isolation.md — FIST 数据目录隔离说明
```

## License

Apache-2.0

## 仓库同步

- **同步/发布只需推 GitCode 即可**：https://gitcode.com/VictorTop/mcpconftest —— GitHub 镜像（https://github.com/vicTop-cw/mcpconftest）由 CI 自动同步（GitCode 根目录 `.sync-to-github` 开关控制，只增不删，以 GitCode 为源覆盖同名分支），**无需手动推送 GitHub，也不要直接改动 GitHub 镜像**。
*（内容由AI生成，仅供参考）*
