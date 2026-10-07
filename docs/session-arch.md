# mcpconftest v0.2 — Session 真实 stdio 通信架构

## 现状

v0.1 的 `Session` 是 stub——返回硬编码的 JSON-RPC 响应，不启动任何子进程。
`check_*` 函数已全部就绪，只差真实 transport 层。

## 设计

### 通信模型

MCP stdio transport（`2026-07-28` 协议 §2.1）：
- 客户端写入 JSON-RPC 请求到子进程 stdin（换行分隔或 Content-Length 帧）
- 子进程回复 JSON-RPC 响应到 stdout（同样分隔）
- 子进程日志/诊断写到 stderr

### FFI 扩展（对比 FIST-Mbt run_check_js.mbt）

FIST-Mbt 的 `js_run_command` 是 **一次性 spawn**（stdio ignore stdin → 等 exit → 返回 JSON）。
我们需要 **持久连接 spawn**（全程 pipe stdin → 反复读写 → 手动 close）。

新增 FFI 函数（`extern "js"`，仅 js target）：

| 函数 | 签名 | 行为 |
|------|------|------|
| `js_spawn_mcp` | `(cmd, workdir) -> Promise<Handle>` | spawn(cmd, [], {cwd, stdio:['pipe','pipe','pipe']}) |
| `js_mcp_write` | `(handle, line) -> Promise<Unit>` | 写一行 JSON + '\n' 到 stdin |
| `js_mcp_read_line` | `(handle, timeout_ms) -> Promise<String>` | 从 stdout 读一行（超时返回空串） |
| `js_mcp_close` | `(handle) -> Promise<Unit>` | kill + 清理 |

### Session 状态机

```
Session {
  handle : Handle       // JS 子进程引用（js target）
  // native target: 桩，编译期占位
}

Session::new(cmd, workdir) -> Session     // js: spawn | native: stub
Session::request(method, params, ms) -> Result[String, String]
Session::notify(method, params) -> Result[Unit, String]
Session::close() -> Result[Unit, String]
```

### request 流程

1. 构造 JSON-RPC 请求 `{"jsonrpc":"2.0","id":N,"method":M,"params":P}`
2. `js_mcp_write(handle, json + "\n")` 写入 stdin
3. `js_mcp_read_line(handle, timeout_ms)` 阻塞读 stdout 一行
4. 返回原始字符串（调用方 `@json.parse`）

### notify 流程

1. 构造 JSON-RPC 通知（无 id 字段）
2. `js_mcp_write` 写入 stdin
3. 不等响应，直接返回 Ok

### 超时 / 错误处理

- 读超时：`js_mcp_read_line` 返回空串 → Session 包装为 `Err("timeout")`
- 子进程 crash / 写失败：JS 端 resolve 带错误标记 → MoonBit 侧 `catch` 转 Err
- `js_mcp_close` 永远成功（kill 吞错），用于 `Session::drop`

### target 策略

| target | 行为 |
|--------|------|
| js | 真实子进程通信（Node `child_process.spawn`） |
| native | stub 桩（`fn js_spawn_mcp(...)` 用 `panic()` 占位，编译通过但运行报错） |

> native target 暂无 spawn 原力，MVP 只保证 js target 可运行。
> `moon.pkg` 配置 `supported_targets = "js"` 避免 native 误用。

### 改动范围

| 文件 | 操作 |
|------|------|
| `src/lib/session.mbt` | 重写：stub → 真实 transport（含 `extern "js"` FFI） |
| `src/lib/session_js.mbt` | 新增：js 目标 inline JS 实现（仿 run_check_js.mbt） |
| `src/lib/session_native.mbt` | 新增：native 目标 panic 桩 |
| `src/lib/moon.pkg` | 新增：target 条件编译配置 |
| `src/lib/checks.mbt` | 不改（接口不变） |
| `src/lib/report.mbt` | 不改 |
| `tests/integration.mbt` | 新增：真实 fixture server 端到端测试 |

### 集成测试

`tests/integration.mbt` 直接调用 `moon run cmd/cli/main -- run --server "node tests/fixtures/echo_server.js"`，验证：
1. initialize 握手通过
2. tools/list 返回有效 schema
3. tools/call 错误路径正确
4. notification 后 server 仍存活

## 工时估算

| 项 | 预估 |
|----|------|
| session_js.mbt FFI + inline JS | 2h |
| session_native.mbt 桩 | 0.5h |
| session.mbt 重写 | 1h |
| 集成测试 + fixture server | 1h |
| 联调 + moon check 通过 | 0.5h |
| **合计** | **5h** |
