# mcpconftest v0.3 — 报告落盘架构

## 目标

e2e / CLI 探测结束后，把完整 CheckResult 结果写入 `--report <dir>` 目录：
`report.json`（机器可读，CI 工件）+ `report.md`（人可读摘要）。

## 设计

### 数据流

```
probe_server / run_all_checks
  → Array[CheckResult]（六类检查的原始结果）
  → @lib.build_report(results, cmd, ver, ts) → Report（含 summary 统计）
  → Report::to_json() / Report::to_markdown()（已有，v0.1 就绪）
  → fs_write(dir + "/report.json", json)      ← v0.3 新增
  → fs_write(dir + "/report.md", md)          ← v0.3 新增
```

### 文件写入 FFI（js target）

`moonbitlang/x/fs` 在 ESM 产物下有 `require` 崩溃风险（FIST-Mbt 探测已实证），
改为自带 `extern "js"` FFI，与 session.mbt 同模式：

| 函数 | 行为 |
|------|------|
| `fs_mkdir_p(dir)` | `fs.mkdirSync(dir, {recursive:true})`，失败返回 -1 |
| `fs_write_file(path, content)` | `fs.writeFileSync(path, content)`，失败返回 -1 |

> 同步 FFI（`fs.writeFileSync` 阻塞但落盘原子），调用链无需 async 化——
> 报告写入在 `async fn main` 尾部调用，同步函数即可。

### CLI 参数

- `--report <dir>`：默认 `./mcpconftest-report`；传 `--report ""` 禁用落盘
- 报告内容含：server_cmd、protocol_version、timestamp、逐条结果、summary 统计

### e2e 集成

`cmd/e2e/main.mbt`：
- `--report <dir>` 参数透传（默认落盘到 `./mcpconftest-report`）
- fixture 模式与 `--server` 模式均落盘
- 落盘失败打印警告但不改变退出码（报告是观测面，不是判据面）

### 验收

1. fixture 回归后 `mcpconftest-report/report.json` 可被 `node -e JSON.parse` 解析
2. `report.md` 含 summary 表与逐条结果
3. ci.sh 全绿
