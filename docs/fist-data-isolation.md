# FIST-Mbt 嵌入数据隔离方案

> 阶段 0（基线固化）产物之一。目的：FIST-Mbt 以库级嵌入 mcpconftest 后，
> 其运行时数据（SqliteStore 生成的 *.db）不得污染仓库工作区。

## 问题

- 此前 FIST 进程级/库级试运行在仓库根目录留下了 `fist-mbt.db`（约 112 KB）。
- 仓库 `.gitignore` 已忽略 `fist-mbt.db*`，但根目录残留影响工作区整洁，
  且一旦在 CI / 用户环境运行会继续在 cwd 生成，行为不可控。

## 方案

1. **运行时数据目录**：默认写入独立目录
   `%LOCALAPPDATA%\mcpconftest\data\`（Windows）/
   `$XDG_DATA_HOME/mcpconftest/data/`（Linux），由 serve 启动时创建。
2. **环境变量覆盖**：`MCPCONFTEST_DATA_DIR` 可显式指定数据目录，
   用于测试隔离与多实例并存。
3. **命名空间**：嵌入的 FistEngine 使用独立 DB 文件
   `mcpconftest-ops.db`，与任何外部 FIST 实例的 `fist-mbt.db` 完全隔离。
4. **遗留清理**：仓库根 `fist-mbt.db` 移入上述数据目录作为一次性迁移，
   并从仓库彻底移除（不跟踪）。

## 落地位置（阶段 2 实施）

- `serve` / `run --server` 启动时解析 `MCPCONFTEST_DATA_DIR` 并初始化 SqliteStore。
- mcpcf.* 内部工具（ops_init/run_batch/verify/watchdog/report/circuit/review）
  全部读写 `mcpconftest-ops.db`。
