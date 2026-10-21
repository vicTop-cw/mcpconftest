# mcpconftest 嵌入引擎数据隔离方案（路线 A：自实现 OpsEngine）

> 阶段 0（基线固化）产物之一。目的：mcpconftest 内嵌的巡检运维引擎
> （路线 A 自实现 OpsEngine，语义对齐 fist-mbt 0.3.6 缓存）的运行时数据
> （SqliteStore 生成的 *.db）不得污染仓库工作区。

## 问题

- 此前 FIST 进程级/库级试运行在仓库根目录留下了 `fist-mbt.db`（约 112 KB）。
- 仓库 `.gitignore` 已忽略 `fist-mbt.db*`，但根目录残留影响工作区整洁，
  且一旦在 CI / 用户环境运行会继续在 cwd 生成，行为不可控。

## 方案

1. **运行时数据目录**：默认写入独立目录
   `%LOCALAPPDATA%\mcpconftest\data\`（Windows）/
   `$XDG_DATA_HOME/mcpconftest/data/`（Linux/macOS），由 serve 启动时创建。
2. **环境变量覆盖**：`MCPCONFTEST_DATA_DIR` 可显式指定数据目录，
   用于测试隔离与多实例并存。
3. **工具级覆盖**：`mcpcf.ops_init` 支持 `data_dir` 参数，显式指定时
   重置引擎并打开该目录下的 `mcpconftest-ops.db`；SQLite 打开失败自动
   回退内存后端（`backend` 字段报 `memory://`）。
4. **命名空间**：自实现引擎使用独立 DB 文件 `mcpconftest-ops.db`，
   与任何外部 FIST 实例的 `fist-mbt.db` 完全隔离。
5. **遗留清理**：仓库根 `fist-mbt.db` 移入上述数据目录作为一次性迁移，
   并从仓库彻底移除（不跟踪）。

## DB schema（自实现 ops_store，与 fist-mbt 0.3.6 逐字一致）

- 建表 SQL 与 fist-mbt 0.3.6 SqliteStore 完全对齐：16 张表
  （`tasks` 等业务表 + `assistant_reg` / `executions` / `file_locks` /
  `lock_violations` 等骨架表），旧 `mcpconftest-ops.db` 可直接复用。
- `tasks` 表 17 列（id / status / description / depth / created_by /
  created_at / updated_at / parent_id / kind / payload / args /
  result / error / attempts / circuit / ns / sub 等），状态字段与
  fist-mbt 九态中文映射一致（待领取 / 执行中 / 已完成 / 失败 / 熔断 等）。
- 所有 SQL 均为参数化绑定（prepared statements），无字符串拼接注入面。

## 落地位置（路线 A 实施）

- 自实现引擎入口：`src/lib/ops_engine.mbt`（OpsEngine）/
  `ops_store.mbt`（OpsMemoryStore / OpsSqliteStore）/
  `ops_task.mbt`（Task / TaskStatus 状态机）。
- 工具接线：`src/lib/fist_ops.mbt` 的 `mcpcf.*` 七工具
  （ops_init/run_batch/verify/watchdog/report/circuit/review）
  全部读写 `mcpconftest-ops.db`，对外签名与数据语义不变。
