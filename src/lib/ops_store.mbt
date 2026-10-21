///
/// ops_store.mbt —— mcpconftest 自实现存储后端（路线 A）。
/// 双后端：Mem（进程内）与 Sql（mcpconftest-ops.db，表结构与 FIST-Mbt 0.3.6
/// 完全一致，可直接复用既有库文件）。移除对 fist-mbt 的包依赖后，本文件
/// 提供 OpsEngine 所需的全部持久化原语：任务 CRUD + 熔断器 upsert/查询。

///|
/// Bytes -> String（UTF-8 解码，容错）
fn ops_str_from_bytes(b : Bytes) -> String {
  @utf8.decode_lossy(b)
}

///|
fn ops_opt_str(o : String?) -> String {
  match o {
    Some(s) => s
    None => ""
  }
}

///|
/// 序列化 Array[String] 为 JSON 数组（经 Json 库转义）
fn ops_array_to_json(arr : Array[String]) -> String {
  Json::array(arr.map(fn(s) { Json::string(s) })).stringify()
}

///|
/// JSON 数组字符串 -> Array[String]（解析失败回退空数组）
fn ops_json_to_array(s : String) -> Array[String] {
  let parsed = @json.parse(s) catch {
    _ => return []
  }
  match parsed {
    Array(items) =>
      items.map(fn(j) {
        match j {
          String(x) => x
          _ => ""
        }
      })
    _ => []
  }
}

///|
/// 内存后端：任务表 + 熔断器表（进程内可变状态）
pub struct OpsMemoryStore {
  tasks : Map[String, Task]
  cbs : Map[String, (String, Int, Int, Int, Int, Int, Int)]
}

///|
fn ops_mem_cb_key(ns : String, circuit : String) -> String {
  ns + "\u0001" + circuit
}

///|
/// SQLite 后端：持有打开的 Database（None 承载打开失败）
pub struct OpsSqliteStore {
  db : @sqlite.Database?
}

///|
/// 统一后端抽象：Mem 或 Sql
pub enum OpsBackend {
  Mem(OpsMemoryStore)
  Sql(OpsSqliteStore)
}

///|
pub fn OpsBackend::backend_name(self : OpsBackend) -> String {
  match self {
    Mem(_) => "memory"
    Sql(_) => "sqlite"
  }
}

///|
/// 打开 SQLite 后端（schema 与 FIST-Mbt 0.3.6 store_sqlite.mbt 逐字一致，
/// 保证既有 mcpconftest-ops.db 无缝复用）。失败返回 None（调用方回退内存）。
pub fn OpsSqliteStore::open(db_path : String) -> OpsSqliteStore? {
  match @sqlite.Database::open(db_path) {
    None => None
    Some(db) => {
      let s : OpsSqliteStore = { db: Some(db), }
      if s.create_schema() {
        s.exec_if_ok("PRAGMA journal_mode=WAL")
        s.exec_if_ok("PRAGMA synchronous=NORMAL")
        s.exec_if_ok("PRAGMA busy_timeout=5000")
        Some(s)
      } else {
        db.close()
        None
      }
    }
  }
}

///|
fn OpsSqliteStore::exec_if_ok(self : OpsSqliteStore, sql : String) -> Unit {
  match self.db {
    None => ()
    Some(db) =>
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
  }
}

///|
/// 初始化 schema（与 FIST-Mbt 0.3.6 相同的建表清单：tasks 完整任务表，
/// circuit_breakers 熔断器表，其余为预置骨架表）。
fn OpsSqliteStore::create_schema(self : OpsSqliteStore) -> Bool {
  let sqls : Array[String] = [
    "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', ns TEXT NOT NULL DEFAULT 'default', priority TEXT NOT NULL DEFAULT '中', importance TEXT NOT NULL DEFAULT '中', depth INTEGER NOT NULL DEFAULT 3, split_n INTEGER NOT NULL DEFAULT 3, status TEXT NOT NULL DEFAULT '待领取', assignee TEXT DEFAULT '', description TEXT NOT NULL DEFAULT '', deliverable TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '', completed_by TEXT DEFAULT '', cleanup_mode TEXT NOT NULL DEFAULT 'deferred', depends_on TEXT NOT NULL DEFAULT '[]')",
    "CREATE TABLE IF NOT EXISTS specs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', spec_type TEXT NOT NULL DEFAULT 'spec', content TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', run_type TEXT NOT NULL DEFAULT 'verify', status TEXT NOT NULL DEFAULT 'running', detail TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL DEFAULT '', finished_at TEXT DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS heartbeats (agent_id TEXT NOT NULL, task_id TEXT NOT NULL, last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', PRIMARY KEY (agent_id, task_id))",
    "CREATE TABLE IF NOT EXISTS heartbeat_history (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL DEFAULT '', interval_sec INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS saga_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ns TEXT NOT NULL DEFAULT 'default', root_task_id TEXT NOT NULL DEFAULT '', step TEXT NOT NULL DEFAULT '', task_id TEXT NOT NULL DEFAULT '', compensation TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', UNIQUE(ns, root_task_id, step))",
    "CREATE TABLE IF NOT EXISTS archive (id TEXT PRIMARY KEY, task_json TEXT NOT NULL DEFAULT '', archived_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS evolve_artifacts (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', goal TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', code TEXT NOT NULL DEFAULT '', score TEXT NOT NULL DEFAULT '0', parts_json TEXT NOT NULL DEFAULT '{}', children INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS call_log (id INTEGER PRIMARY KEY AUTOINCREMENT, seq INTEGER, ts TEXT, tool TEXT, caller TEXT, ns TEXT, params_json TEXT, result_json TEXT, ok INTEGER, runtime_ms INTEGER)",
    "CREATE TABLE IF NOT EXISTS reservations (scope TEXT PRIMARY KEY, agent TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS executors (name TEXT PRIMARY KEY, abilities_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS circuit_breakers (ns TEXT NOT NULL DEFAULT 'default', circuit TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'closed', failures INTEGER NOT NULL DEFAULT 0, window_secs INTEGER NOT NULL DEFAULT 60, threshold INTEGER NOT NULL DEFAULT 3, recovery_secs INTEGER NOT NULL DEFAULT 30, opened_at INTEGER NOT NULL DEFAULT 0, last_fail_ts INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT '', PRIMARY KEY (ns, circuit))",
    "CREATE TABLE IF NOT EXISTS assistant_reg (agent TEXT PRIMARY KEY, mode TEXT NOT NULL DEFAULT 'all', is_primary INTEGER NOT NULL DEFAULT 0, registered_at TEXT NOT NULL DEFAULT '', heartbeat_at TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')",
    "CREATE TABLE IF NOT EXISTS executions (\n    id TEXT PRIMARY KEY,\n    task_id TEXT NOT NULL DEFAULT '',\n    executor TEXT NOT NULL DEFAULT 'manual',\n    model TEXT NOT NULL DEFAULT '',\n    tokens_in INTEGER NOT NULL DEFAULT 0,\n    tokens_out INTEGER NOT NULL DEFAULT 0,\n    cost TEXT NOT NULL DEFAULT '0.0',\n    duration_ms INTEGER NOT NULL DEFAULT 0,\n    rate_limited INTEGER NOT NULL DEFAULT 0,\n    failure_reason TEXT NOT NULL DEFAULT '',\n    created_at TEXT NOT NULL DEFAULT ''\n)",
    "CREATE TABLE IF NOT EXISTS file_locks (scope TEXT PRIMARY KEY, lock_id TEXT NOT NULL DEFAULT '', batch_id TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', ts TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', meta TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS lock_violations (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', scope TEXT NOT NULL DEFAULT '', reason TEXT NOT NULL DEFAULT '', lock_id TEXT NOT NULL DEFAULT '')",
  ]
  match self.db {
    None => false
    Some(db) => {
      let mut ok = true
      for s in sqls {
        if !db.exec(s) {
          ok = false
        }
      }
      ok
    }
  }
}

///|
fn ops_task_columns() -> String {
  "id, parent_id, project_dir, ns, priority, importance, depth, split_n, status, assignee, description, deliverable, created_at, updated_at, completed_by, cleanup_mode, depends_on"
}

///|
/// SQLite 行 -> Task（列顺序与 task_columns 一致；空串字段转 None）
fn ops_row_to_task(stmt : @sqlite.Statement) -> Task {
  let parent_raw = ops_str_from_bytes(stmt.column_text(1))
  let assignee_raw = ops_str_from_bytes(stmt.column_text(9))
  let completed_raw = ops_str_from_bytes(stmt.column_text(14))
  let depends_raw = ops_str_from_bytes(stmt.column_text(16))
  Task::from_db(
    ops_str_from_bytes(stmt.column_text(0)),
    if parent_raw == "" { None } else { Some(parent_raw) },
    ops_str_from_bytes(stmt.column_text(2)),
    ops_str_from_bytes(stmt.column_text(3)),
    ops_str_from_bytes(stmt.column_text(4)),
    ops_str_from_bytes(stmt.column_text(5)),
    stmt.column_int(6),
    stmt.column_int(7),
    ops_str_from_bytes(stmt.column_text(8)),
    if assignee_raw == "" { None } else { Some(assignee_raw) },
    ops_str_from_bytes(stmt.column_text(10)),
    ops_str_from_bytes(stmt.column_text(11)),
    ops_str_from_bytes(stmt.column_text(12)),
    ops_str_from_bytes(stmt.column_text(13)),
    if completed_raw == "" { None } else { Some(completed_raw) },
    ops_str_from_bytes(stmt.column_text(15)),
    ops_json_to_array(depends_raw),
  )
}

///|
fn ops_bind_task_values(stmt : @sqlite.Statement, t : Task) -> Unit {
  ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(t.get_id()))))
  ignore(stmt.bind(2, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.get_parent())))))
  ignore(stmt.bind(3, @sqlite.SqlValue::Text(@utf8.encode(t.get_project_dir()))))
  ignore(stmt.bind(4, @sqlite.SqlValue::Text(@utf8.encode(t.get_ns()))))
  ignore(stmt.bind(5, @sqlite.SqlValue::Text(@utf8.encode(t.priority))))
  ignore(stmt.bind(6, @sqlite.SqlValue::Text(@utf8.encode(t.importance))))
  ignore(stmt.bind(7, @sqlite.SqlValue::Int(t.get_depth())))
  ignore(stmt.bind(8, @sqlite.SqlValue::Int(t.split_n)))
  ignore(stmt.bind(9, @sqlite.SqlValue::Text(@utf8.encode(t.status_to_string()))))
  ignore(stmt.bind(10, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.get_assignee())))))
  ignore(stmt.bind(11, @sqlite.SqlValue::Text(@utf8.encode(t.get_description()))))
  ignore(stmt.bind(12, @sqlite.SqlValue::Text(@utf8.encode(t.get_deliverable()))))
  ignore(stmt.bind(13, @sqlite.SqlValue::Text(@utf8.encode(t.created_at))))
  ignore(stmt.bind(14, @sqlite.SqlValue::Text(@utf8.encode(t.get_updated_at()))))
  ignore(stmt.bind(15, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.completed_by)))))
  ignore(stmt.bind(16, @sqlite.SqlValue::Text(@utf8.encode(t.cleanup_mode))))
  ignore(stmt.bind(17, @sqlite.SqlValue::Text(@utf8.encode(ops_array_to_json(t.depends_on)))))
}

///|
/// UPDATE 专用绑定：SET 列顺序（parent_id..depends_on）+ WHERE id
fn ops_bind_task_update_values(stmt : @sqlite.Statement, t : Task) -> Unit {
  ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.get_parent())))))
  ignore(stmt.bind(2, @sqlite.SqlValue::Text(@utf8.encode(t.get_project_dir()))))
  ignore(stmt.bind(3, @sqlite.SqlValue::Text(@utf8.encode(t.get_ns()))))
  ignore(stmt.bind(4, @sqlite.SqlValue::Text(@utf8.encode(t.priority))))
  ignore(stmt.bind(5, @sqlite.SqlValue::Text(@utf8.encode(t.importance))))
  ignore(stmt.bind(6, @sqlite.SqlValue::Int(t.get_depth())))
  ignore(stmt.bind(7, @sqlite.SqlValue::Int(t.get_split_n())))
  ignore(stmt.bind(8, @sqlite.SqlValue::Text(@utf8.encode(t.status_to_string()))))
  ignore(stmt.bind(9, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.get_assignee())))))
  ignore(stmt.bind(10, @sqlite.SqlValue::Text(@utf8.encode(t.get_description()))))
  ignore(stmt.bind(11, @sqlite.SqlValue::Text(@utf8.encode(t.get_deliverable()))))
  ignore(stmt.bind(12, @sqlite.SqlValue::Text(@utf8.encode(t.created_at))))
  ignore(stmt.bind(13, @sqlite.SqlValue::Text(@utf8.encode(t.get_updated_at()))))
  ignore(stmt.bind(14, @sqlite.SqlValue::Text(@utf8.encode(ops_opt_str(t.completed_by)))))
  ignore(stmt.bind(15, @sqlite.SqlValue::Text(@utf8.encode(t.cleanup_mode))))
  ignore(stmt.bind(16, @sqlite.SqlValue::Text(@utf8.encode(ops_array_to_json(t.depends_on)))))
}

/// —— OpsBackend 统一接口 ——

///|
pub fn OpsBackend::create_task(self : OpsBackend, task : Task) -> Result[Unit, String] {
  match self {
    Mem(ms) => {
      if ms.tasks.contains(task.get_id()) {
        return Err("task already exists: \{task.get_id()}")
      }
      ms.tasks.set(task.get_id(), task)
      Ok(())
    }
    Sql(ss) =>
      match ss.db {
        None => Err("sqlite store 未打开")
        Some(db) => {
          if ss.get_task(task.get_id()) is Some(_) {
            return Err("task already exists: \{task.get_id()}")
          }
          let sql = "INSERT INTO tasks (\{ops_task_columns()}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
          match db.prepare(sql) {
            None => Err("sqlite prepare 失败: create_task")
            Some(stmt) => {
              ops_bind_task_values(stmt, task)
              let exec_ok = stmt.execute()
              stmt.finalize()
              if exec_ok {
                Ok(())
              } else {
                Err("sqlite 写入失败: \{task.get_id()}")
              }
            }
          }
        }
      }
  }
}

///|
pub fn OpsBackend::get_task(self : OpsBackend, id : String) -> Task? {
  match self {
    Mem(ms) => ms.tasks.get(id)
    Sql(ss) => ss.get_task(id)
  }
}

///|
pub fn OpsBackend::update_task(self : OpsBackend, task : Task) -> Result[Unit, String] {
  match self {
    Mem(ms) => {
      if !ms.tasks.contains(task.get_id()) {
        return Err("task not found: \{task.get_id()}")
      }
      ms.tasks.set(task.get_id(), task)
      Ok(())
    }
    Sql(ss) => ss.update_task(task)
  }
}

///|
pub fn OpsBackend::list_tasks(self : OpsBackend) -> Array[Task] {
  match self {
    Mem(ms) => {
      let out : Array[Task] = []
      for (_, t) in ms.tasks {
        out.push(t)
      }
      out
    }
    Sql(ss) => ss.list_tasks()
  }
}

///|
/// 列出指定命名空间的任务（空 ns 回退 default，与 FIST-Mbt BUG-85 口径一致）
pub fn OpsBackend::list_tasks_in(self : OpsBackend, ns : String) -> Array[Task] {
  let eff = if ns == "" { "default" } else { ns }
  match self {
    Mem(ms) => {
      let out : Array[Task] = []
      for (_, t) in ms.tasks {
        if t.get_ns() == eff {
          out.push(t)
        }
      }
      out
    }
    Sql(ss) => ss.list_tasks_in(eff)
  }
}

///|
pub fn OpsBackend::cb_get(
  self : OpsBackend,
  ns : String,
  circuit : String,
) -> (String, Int, Int, Int, Int, Int, Int)? {
  match self {
    Mem(ms) => ms.cbs.get(ops_mem_cb_key(ns, circuit))
    Sql(ss) => ss.cb_get(ns, circuit)
  }
}

///|
pub fn OpsBackend::cb_save(
  self : OpsBackend,
  ns : String,
  circuit : String,
  state : String,
  failures : Int,
  window_secs : Int,
  threshold : Int,
  recovery_secs : Int,
  opened_at : Int,
  last_fail_ts : Int,
  updated_at : String,
) -> Result[Unit, String] {
  match self {
    Mem(ms) => {
      ms.cbs.set(
        ops_mem_cb_key(ns, circuit),
        (state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts),
      )
      Ok(())
    }
    Sql(ss) => ss.cb_save(
      ns,
      circuit,
      state,
      failures,
      window_secs,
      threshold,
      recovery_secs,
      opened_at,
      last_fail_ts,
      updated_at,
    )
  }
}

/// —— Sql 后端内部实现 ——

///|
fn OpsSqliteStore::get_task(self : OpsSqliteStore, id : String) -> Task? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT \{ops_task_columns()} FROM tasks WHERE id = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(id))))
          let found = if stmt.step() { Some(ops_row_to_task(stmt)) } else { None }
          stmt.finalize()
          found
        }
      }
    }
  }
}

///|
fn OpsSqliteStore::update_task(
  self : OpsSqliteStore,
  task : Task,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if self.get_task(task.get_id()) is None {
        return Err("task not found: \{task.get_id()}")
      }
      let sql = "UPDATE tasks SET parent_id = ?, project_dir = ?, ns = ?, priority = ?, importance = ?, depth = ?, split_n = ?, status = ?, assignee = ?, description = ?, deliverable = ?, created_at = ?, updated_at = ?, completed_by = ?, cleanup_mode = ?, depends_on = ? WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_task")
        Some(stmt) => {
          ops_bind_task_update_values(stmt, task)
          ignore(stmt.bind(17, @sqlite.SqlValue::Text(@utf8.encode(task.get_id()))))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 更新失败: \{task.get_id()}")
          }
        }
      }
    }
  }
}

///|
fn OpsSqliteStore::list_tasks(self : OpsSqliteStore) -> Array[Task] {
  let out : Array[Task] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT \{ops_task_columns()} FROM tasks"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(ops_row_to_task(stmt))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
fn OpsSqliteStore::list_tasks_in(
  self : OpsSqliteStore,
  ns : String,
) -> Array[Task] {
  let out : Array[Task] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT \{ops_task_columns()} FROM tasks WHERE ns = ?"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(ns))))
          while stmt.step() {
            out.push(ops_row_to_task(stmt))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
pub fn OpsSqliteStore::cb_get(
  self : OpsSqliteStore,
  ns : String,
  circuit : String,
) -> (String, Int, Int, Int, Int, Int, Int)? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts FROM circuit_breakers WHERE ns = ? AND circuit = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(ns))))
          ignore(stmt.bind(2, @sqlite.SqlValue::Text(@utf8.encode(circuit))))
          let mut row : (String, Int, Int, Int, Int, Int, Int)? = None
          if stmt.step() {
            row = Some(
              (
                ops_str_from_bytes(stmt.column_text(0)),
                stmt.column_int(1),
                stmt.column_int(2),
                stmt.column_int(3),
                stmt.column_int(4),
                stmt.column_int(5),
                stmt.column_int(6),
              ),
            )
          }
          stmt.finalize()
          row
        }
      }
    }
  }
}

///|
pub fn OpsSqliteStore::cb_save(
  self : OpsSqliteStore,
  ns : String,
  circuit : String,
  state : String,
  failures : Int,
  window_secs : Int,
  threshold : Int,
  recovery_secs : Int,
  opened_at : Int,
  last_fail_ts : Int,
  updated_at : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO circuit_breakers (ns, circuit, state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(ns, circuit) DO UPDATE SET state=excluded.state, failures=excluded.failures, window_secs=excluded.window_secs, threshold=excluded.threshold, recovery_secs=excluded.recovery_secs, opened_at=excluded.opened_at, last_fail_ts=excluded.last_fail_ts, updated_at=excluded.updated_at"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: cb_save")
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@utf8.encode(ns))))
          ignore(stmt.bind(2, @sqlite.SqlValue::Text(@utf8.encode(circuit))))
          ignore(stmt.bind(3, @sqlite.SqlValue::Text(@utf8.encode(state))))
          ignore(stmt.bind(4, @sqlite.SqlValue::Int(failures)))
          ignore(stmt.bind(5, @sqlite.SqlValue::Int(window_secs)))
          ignore(stmt.bind(6, @sqlite.SqlValue::Int(threshold)))
          ignore(stmt.bind(7, @sqlite.SqlValue::Int(recovery_secs)))
          ignore(stmt.bind(8, @sqlite.SqlValue::Int(opened_at)))
          ignore(stmt.bind(9, @sqlite.SqlValue::Int(last_fail_ts)))
          ignore(stmt.bind(10, @sqlite.SqlValue::Text(@utf8.encode(updated_at))))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入熔断器失败")
          }
        }
      }
    }
  }
}
