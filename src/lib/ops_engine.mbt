///
/// ops_engine.mbt —— mcpconftest 自实现 FIST 兼容引擎（路线 A）。
/// 对外语义与 FIST-Mbt 0.3.6 FistEngine 对齐：publish/verify/list*/get_task/
/// children_of/熔断器三态/heartbeat_backend/docs 门禁。store 层见 ops_store.mbt，
/// 任务模型与状态机见 ops_task.mbt。

///|
pub struct OpsEngine {
  store : OpsBackend
}

///|
/// 打开 SQLite 后端引擎（失败回退由调用方处理，返回 None）
pub fn OpsEngine::open_sqlite(db_path : String) -> OpsEngine? {
  match OpsSqliteStore::open(db_path) {
    None => None
    Some(s) => Some({ store: Sql(s), })
  }
}

///|
/// 内存后端引擎（SQLite 打开失败时的回退）
pub fn OpsEngine::new() -> OpsEngine {
  {
    store: Mem({ tasks: Map::new(), cbs: Map::new(), }),
  }
}

///|
pub fn OpsEngine::heartbeat_backend(self : OpsEngine) -> String {
  self.store.backend_name()
}

///|
/// 根任务 id 固定为 T0（与 FIST-Mbt root_task_id 一致）
pub fn root_task_id() -> String {
  "T0"
}

///|
/// 生成下一轮根任务 id（T0 -> T0r2 -> T0r3 ...）
fn OpsEngine::next_round_id(self : OpsEngine) -> String {
  let base = root_task_id()
  let mut round = 1
  let mut candidate = "\{base}r\{round + 1}"
  let mut taken = true
  while taken {
    match self.store.get_task(candidate) {
      Some(_) => {
        round = round + 1
        if round >= 100000 {
          return candidate
        }
        candidate = "\{base}r\{round + 1}"
      }
      None => taken = false
    }
  }
  candidate
}

///|
/// 全局第一个空闲的根任务 id：T0 空闲则用 T0，否则顺延 T0r2、T0r3 ...
fn OpsEngine::first_free_root_id(self : OpsEngine) -> String {
  let base = root_task_id()
  match self.store.get_task(base) {
    None => base
    Some(_) => self.next_round_id()
  }
}

///|
/// 发布根任务（一次巡检批次）。仅限人类指挥官。
pub fn OpsEngine::publish(
  self : OpsEngine,
  project_dir~ : String,
  description~ : String,
  created_by~ : String,
  now~ : String,
  ns? : String = "default",
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官（created_by=human_steward）")
  }
  let id = self.first_free_root_id()
  let t = Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

///|
/// 列出某任务的所有直接子任务
pub fn OpsEngine::children_of(
  self : OpsEngine,
  task_id : String,
) -> Array[Task] {
  let out : Array[Task] = []
  for t in self.store.list_tasks() {
    match t.get_parent() {
      Some(p) => if p == task_id { out.push(t) }
      None => ()
    }
  }
  out
}

///|
/// 非叶节点且所有直接子任务都已完成
pub fn OpsEngine::all_subtasks_completed(
  self : OpsEngine,
  parent : Task,
) -> Bool {
  let children = self.children_of(parent.get_id())
  if children.is_empty() {
    return false
  }
  children.all(fn(t) { t.get_status().is_completed() })
}

///|
/// 验收（verifier）：Reviewing -> Completed；若父任务全部子任务完成则父任务自动待验收。
pub fn OpsEngine::verify(
  self : OpsEngine,
  task_id~ : String,
  verifier~ : String,
  now~ : String,
  docs_check? : Bool = false,
) -> Result[Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      // Omega 强验证门禁（默认关闭）：description 含 [omega:required] 时须先有已通过复验
      match self.omega_verify_gate(task_id) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // 外部判据闸门（默认关闭）：[gate:required] 须有服务端真实执行记录
      match self.gate_verify_gate(task_id) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // 「文档即实现」门禁（默认关闭）：仅 docs_check=true 时校验
      if docs_check {
        match self.docs_verify_gate(task_id) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
      if !t.get_status().is_reviewing() {
        return Err(
          "非法验收: 任务处于 [\{t.status_to_string()}]，需先 submit",
        )
      }
      let c = match t.complete(completed_by=verifier) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("验收落库失败: \{e}")
      }
      // 向上归并：父任务全部子任务完成后自动待验收。
      // 父任务被拆后即非执行中（通常是 Pending/待领取），归并是收敛语义，
      // 此处覆盖式进入 Executing，避免 execute 拒绝被静默吞掉后 submit 必败。
      match c2.get_parent() {
        Some(pid) =>
          match self.store.get_task(pid) {
            Some(parent) =>
              if self.all_subtasks_completed(parent) {
                let pe = match parent.execute() {
                  Ok(x) => x
                  Err(_) => { ..parent, status: Executing, }
                }
                let pe = if pe.get_deliverable() == "" {
                  let kids = self.children_of(pe.get_id())
                  let merged = if kids.is_empty() {
                    "（子任务均已完成，无文字交付物）"
                  } else {
                    kids
                    .map(fn(t) { "[\{t.get_id()}] \{t.get_deliverable()}" })
                    .join("\n")
                  }
                  pe.with_deliverable(merged, now)
                } else {
                  pe
                }
                match pe.submit() {
                  Ok(p2) => {
                    match self.store.update_task(p2.with_updated_at(now)) {
                      Ok(_) => ()
                      Err(e) => return Err("父任务归并落库失败: \{e}")
                    }
                    Ok(c2)
                  }
                  Err(e) => Err(e)
                }
              } else {
                Ok(c2)
              }
            None => Ok(c2)
          }
        None => Ok(c2)
      }
    }
  }
}

///|
/// 按命名空间列出任务（空 ns 回退 default）
pub fn OpsEngine::list_in_ns(self : OpsEngine, ns : String) -> Array[Task] {
  self.store.list_tasks_in(ns)
}

///|
pub fn OpsEngine::list_all(self : OpsEngine) -> Array[Task] {
  self.store.list_tasks()
}

///|
pub fn OpsEngine::list_by_status(
  self : OpsEngine,
  st : TaskStatus,
) -> Array[Task] {
  let out : Array[Task] = []
  for t in self.store.list_tasks() {
    if t.get_status() == st {
      out.push(t)
    }
  }
  out
}

///|
pub fn OpsEngine::get_task(self : OpsEngine, id : String) -> Task? {
  self.store.get_task(id)
}

/// —— 熔断器三态（与 engine_circuit.mbt 语义逐字对齐） ——

///|
pub fn OpsEngine::circuit_fail(
  self : OpsEngine,
  ns~ : String,
  circuit~ : String,
  now_secs~ : Int,
  window_secs? : Int = 60,
  threshold? : Int = 3,
  recovery_secs? : Int = 30,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
    None => ("closed", 0, window_secs, threshold, recovery_secs, 0, 0)
    Some(r) => r
  }
  let (new_state, new_failures, new_opened) = if state == "open" {
    ("open", failures, opened_at)
  } else if state == "half_open" {
    ("open", thr, now_secs)
  } else {
    let nf = if now_secs - last_fail_ts > w { 1 } else { failures + 1 }
    if nf >= thr {
      ("open", nf, now_secs)
    } else {
      ("closed", nf, 0)
    }
  }
  ignore(
    self.store.cb_save(
      ns,
      circuit,
      new_state,
      new_failures,
      w,
      thr,
      rec,
      new_opened,
      now_secs,
      now_secs.to_string(),
    ),
  )
  ops_cb_json(
    circuit,
    new_state,
    new_failures,
    w,
    thr,
    rec,
    new_opened,
    now_secs,
  )
}

///|
pub fn OpsEngine::circuit_succeed(
  self : OpsEngine,
  ns~ : String,
  circuit~ : String,
  now_secs~ : Int,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
    None => ("closed", 0, 60, 3, 30, 0, 0)
    Some(r) => r
  }
  let (new_state, new_failures, new_opened) = if state == "half_open" {
    ("closed", 0, 0)
  } else if state == "open" {
    ("open", failures, opened_at)
  } else {
    ("closed", 0, 0)
  }
  ignore(
    self.store.cb_save(
      ns,
      circuit,
      new_state,
      new_failures,
      w,
      thr,
      rec,
      new_opened,
      now_secs,
      now_secs.to_string(),
    ),
  )
  ops_cb_json(
    circuit,
    new_state,
    new_failures,
    w,
    thr,
    rec,
    new_opened,
    now_secs,
  )
}

///|
pub fn OpsEngine::circuit_status(
  self : OpsEngine,
  ns~ : String,
  circuit~ : String,
  now_secs~ : Int,
  probe_limit? : Int = 1,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_ts) = match row {
    None => ("closed", 0, 60, 3, 30, 0, 0)
    Some(r) => r
  }
  let (eff_state, eff_failures) = if state == "open" && opened_at > 0 &&
    now_secs - opened_at >= rec {
    ignore(
      self.store.cb_save(
        ns,
        circuit,
        "half_open",
        0,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        now_secs.to_string(),
      ),
    )
    ("half_open", 0)
  } else {
    (state, failures)
  }
  if eff_state != "half_open" {
    ops_cb_json(
      circuit,
      eff_state,
      eff_failures,
      w,
      thr,
      rec,
      opened_at,
      now_secs,
    )
  } else {
    let stale = rec > 0 && last_ts > 0 && now_secs - last_ts >= rec
    let granted = if stale { 0 } else { eff_failures }
    if probe_limit <= 0 || granted < probe_limit {
      ignore(
        self.store.cb_save(
          ns,
          circuit,
          "half_open",
          granted + 1,
          w,
          thr,
          rec,
          opened_at,
          now_secs,
          now_secs.to_string(),
        ),
      )
      ops_cb_json(
        circuit,
        "half_open",
        granted + 1,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        probe_limit~,
      )
    } else {
      ops_cb_json(
        circuit,
        "half_open",
        granted,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        probe_limit~,
        deny=true,
      )
    }
  }
}

///|
fn ops_cb_json(
  circuit : String,
  state : String,
  failures : Int,
  w : Int,
  thr : Int,
  rec : Int,
  opened_at : Int,
  now_secs : Int,
  probe_limit? : Int = 1,
  deny? : Bool = false,
) -> Json {
  let allow = state != "open" && not(deny)
  let probes = if state == "half_open" { failures } else { 0 }
  let m = Map::new()
  m.set("circuit", Json::string(circuit))
  m.set("state", Json::string(state))
  m.set("failures", Json::number(failures.to_double()))
  m.set("window_secs", Json::number(w.to_double()))
  m.set("threshold", Json::number(thr.to_double()))
  m.set("recovery_secs", Json::number(rec.to_double()))
  m.set("opened_at", Json::number(opened_at.to_double()))
  m.set("allow_call", Json::boolean(allow))
  m.set("probes_granted", Json::number(probes.to_double()))
  m.set("probe_limit", Json::number(probe_limit.to_double()))
  m.set(
    "note",
    Json::string(
      "熔断器三态（Nygard Release It! 2007 / Fowler / Azure 蒸馏）：Closed 放行 / Open fail-fast 拒绝 / Half-Open 只放行 probe_limit 次探测（默认 1），探测成功回 Closed、失败回 Open；半开态下 failures=probes_granted（已放行探测数，不是失败数），配额用尽即 allow_call=false，超过一个 recovery 窗无上报则重置。",
    ),
  )
  Json::object(m)
}

/// —— 门禁（与 FIST-Mbt 语义对齐，默认关闭） ——

///|
fn ops_omega_mark() -> String {
  "[omega:required]"
}

///|
fn ops_gate_mark() -> String {
  "[gate:required]"
}

///|
fn ops_collect_failures(results : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for j in results {
    let mut item = "<unknown>"
    let mut detail = ""
    match j {
      Object(m) => {
        item = match m.get("item") {
          Some(String(s)) => s
          _ => "<unknown>"
        }
        detail = match m.get("detail") {
          Some(String(s)) => s
          _ => ""
        }
      }
      _ => ()
    }
    let ok = match j {
      Object(m) =>
        match m.get("passed") {
          Some(True) => true
          _ => false
        }
      _ => false
    }
    if !ok {
      out.push("\{item}: \{detail}")
    }
  }
  out
}

///|
/// 项目结构验证（README.md / CHANGELOG.md / reports/ 存在性）
fn ops_check_structure(project_dir : String) -> Array[Json] {
  let results : Array[Json] = []
  let dir_ok = @fs.path_exists(project_dir)
  if !dir_ok {
    results.push(
      Json::object({
        "item": Json::string("project_dir"),
        "passed": Json::boolean(false),
        "detail": Json::string("目录不存在: \{project_dir}"),
      }),
    )
    return results
  }
  let required_items : Array[String] = [
    "README.md",
    "CHANGELOG.md",
    "reports",
  ]
  for item in required_items {
    let sep = if project_dir.contains("\\") { "\\" } else { "/" }
    let path = project_dir + sep + item
    let exists = @fs.path_exists(path)
    results.push(
      Json::object({
        "item": Json::string("必填项: \{item}"),
        "passed": Json::boolean(exists),
        "detail": Json::string(if exists { "存在" } else { "缺失" }),
      }),
    )
  }
  results
}

///|
/// 回传文本五段式校验
fn ops_check_report_format(text : String) -> Array[Json] {
  let results : Array[Json] = []
  if text.trim().is_empty() {
    results.push(
      Json::object({
        "item": Json::string("回传文本"),
        "passed": Json::boolean(false),
        "detail": Json::string("回传为空"),
      }),
    )
    return results
  }
  let required_report_sections : Array[String] = [
    "结论",
    "证据",
    "分析",
    "缺口与风险",
    "建议入档位置",
  ]
  for section in required_report_sections {
    let found = text.contains(section)
    results.push(
      Json::object({
        "item": Json::string("回传段: \{section}"),
        "passed": Json::boolean(found),
        "detail": Json::string(if found { "包含" } else { "缺失" }),
      }),
    )
  }
  results
}

///|
/// 「文档即实现」验收门禁：仅 docs_check=true 时生效。
fn OpsEngine::docs_verify_gate(
  self : OpsEngine,
  task_id : String,
) -> Result[Unit, String] {
  let t = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(x) => x
  }
  let fail_buf : Array[String] = []
  let proj = t.get_project_dir()
  if proj.is_empty() {
    fail_buf.push("project_dir 为空，无法校验项目结构")
  } else {
    let struct_res = ops_check_structure(proj)
    let f1 = ops_collect_failures(struct_res)
    for x in f1 {
      fail_buf.push(x)
    }
  }
  let dlv = t.get_deliverable()
  let fmt_res = ops_check_report_format(dlv)
  let f2 = ops_collect_failures(fmt_res)
  for x in f2 {
    fail_buf.push(x)
  }
  if fail_buf.is_empty() {
    Ok(())
  } else {
    Err("文档一致性门禁未通过：\{fail_buf.join("；")}")
  }
}

///|
/// Omega 强验证门禁（默认关闭）：description 含 [omega:required] 时须先有已通过成果复验。
/// mcpcf 七工具面无复验写入入口，与 FIST-Mbt 在该工具集语境下的行为一致：直接拒绝。
fn OpsEngine::omega_verify_gate(
  self : OpsEngine,
  task_id : String,
) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Ok(())
    Some(t) =>
      if t.get_description().contains(ops_omega_mark()) {
        Err(
          "Omega 强验证门禁：任务 [\{task_id}] 尚未做成果复验，请先由验证者执行 omega_result_verify",
        )
      } else {
        Ok(())
      }
  }
}

///|
/// 外部判据闸门（默认关闭）：[gate:required] 须有服务端真实执行记录。
/// mcpcf 七工具面无 run_check 写入入口，与 FIST-Mbt 在该工具集语境下的行为一致：直接拒绝。
fn OpsEngine::gate_verify_gate(
  self : OpsEngine,
  task_id : String,
) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Ok(())
    Some(t) =>
      if t.get_description().contains(ops_gate_mark()) {
        Err(
          "外部判据闸门：任务 [\{task_id}] 带 [gate:required]，但尚无外部检查记录。请先由服务端执行 run_check（真实运行外部命令并落库）",
        )
      } else {
        Ok(())
      }
  }
}
