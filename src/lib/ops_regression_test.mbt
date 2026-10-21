///|
/// ops_regression_test.mbt —— 路线 A 自实现引擎回归测试（in-package，@lib 前缀访问）。
/// 覆盖：状态机全链路与非法迁移、verify 父任务归并（回归 P2：Pending 父任务
/// 收敛被静默吞错）、熔断器三态流转、SQLite schema 与 fist-mbt 0.3.6 表级对齐。
/// 注：TaskStatus 枚举变体为只读（包外不可构造），断言统一走 is_* 方法 + 中文映射。

///|
fn[T, E] r_is_err(r : Result[T, E]) -> Bool {
  match r {
    Err(_) => true
    _ => false
  }
}

///|
fn[T] must_some(o : Option[T]) -> T {
  match o {
    Some(x) => x
    None => panic()
  }
}

///|
fn cb_state(j : Json) -> String {
  match j {
    Object(m) =>
      match m.get("state") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn[T] must_ok(r : Result[T, String]) -> T {
  match r {
    Ok(x) => x
    Err(e) => panic()
  }
}

///|
/// 状态机全链路：待领取→已领取→拆分中→执行中→待验收→已完成→已归档。
test "ops_state_machine_full_flow" {
  let t = @lib.Task::new(
    id="T100",
    project_dir="D:/proj",
    description="full",
    depth=3,
  )
  let c1 = must_ok(t.claim(assignee="alice"))
  assert_eq(c1.get_status().is_claimed(), true)
  let c2 = must_ok(c1.split())
  assert_eq(c2.get_status().is_splitting(), true)
  let c3 = must_ok(c2.execute())
  assert_eq(c3.get_status().is_executing(), true)
  let c4 = must_ok(c3.submit())
  assert_eq(c4.get_status().is_reviewing(), true)
  let c5 = must_ok(c4.complete(completed_by="bob"))
  assert_eq(c5.get_status().is_completed(), true)
  assert_eq(c5.get_status().to_string(), "已完成")
  assert_eq(c5.get_assignee(), Some("alice"))
  assert_eq(c5.get_depth(), 3)
  let c6 = must_ok(c5.archive())
  assert_eq(c6.get_status().is_archived(), true)
}

///|
/// 非法迁移拒绝 + 边界容错：
/// Pending 不可 execute/submit/complete；claim 需要非空身份；原子任务不可拆分；
/// from_db 收到未知状态字符串回退 Pending（不崩溃）。
test "ops_state_machine_invalid_transitions" {
  let t = @lib.Task::new(
    id="T101",
    project_dir="D:/proj",
    description="inv",
  )
  assert_eq(r_is_err(t.execute()), true)
  assert_eq(r_is_err(t.submit()), true)
  assert_eq(r_is_err(t.complete(completed_by="bob")), true)
  assert_eq(r_is_err(t.claim(assignee="")), true)
  let leaf = @lib.Task::new(id="T102", project_dir="D:/proj", depth=1)
  let lc = must_ok(leaf.claim(assignee="alice"))
  assert_eq(r_is_err(lc.split()), true)
  let t2 = @lib.Task::from_db(
    "T103",
    None,
    "D:/p",
    "default",
    "中",
    "中",
    3,
    3,
    "幽灵状态",
    None,
    "d",
    "",
    "",
    "",
    None,
    "deferred",
    [],
  )
  assert_eq(t2.get_status().is_pending(), true)
}

///|
/// verify 父任务归并（回归 P2）：父任务为 Pending 时，子任务全部验收完成后
/// 父任务应收敛为待验收并合并子任务交付物，而不是报非法迁移。
test "ops_verify_parent_merge" {
  let e = @lib.OpsEngine::new()
  let pid = must_ok(
    e.publish(
      project_dir="D:/p",
      description="parent batch",
      created_by="human_steward",
      now="2026-10-21T00:00:00Z",
    ),
  )
  assert_eq(pid, "T0")
  let kid = @lib.Task::new(
    id="T0.1",
    project_dir="D:/p",
    description="kid",
    depth=2,
    parent_id=pid,
    created_at="2026-10-21T00:00:00Z",
  )
  let k1 = must_ok(kid.claim(assignee="alice"))
  let k2 = must_ok(k1.split())
  let k3 = must_ok(k2.execute())
  let k4 = k3.with_deliverable("kid deliverable", "2026-10-21T01:00:00Z")
  let k5 = must_ok(k4.submit())
  assert_eq(r_is_err(e.store.create_task(k5)), false)
  let p0 = must_some(e.get_task("T0"))
  assert_eq(p0.get_status().is_pending(), true)
  assert_eq(r_is_err(e.verify(task_id="T0.1", verifier="bob", now="2026-10-21T02:00:00Z")), false)
  let parent = must_some(e.get_task("T0"))
  assert_eq(parent.get_status().is_reviewing(), true)
  assert_eq(parent.get_deliverable().contains("[T0.1]"), true)
  let kid_done = must_some(e.get_task("T0.1"))
  assert_eq(kid_done.get_status().is_completed(), true)
}

///|
/// 熔断器三态流转：closed→(3 次失败)→open→(达到恢复窗)→half_open→探测成功→closed。
test "ops_circuit_breaker_flow" {
  let e = @lib.OpsEngine::new()
  let j1 = e.circuit_fail(ns="ns1", circuit="c1", now_secs=100)
  assert_eq(cb_state(j1), "closed")
  let j2 = e.circuit_fail(ns="ns1", circuit="c1", now_secs=101)
  assert_eq(cb_state(j2), "closed")
  let j3 = e.circuit_fail(ns="ns1", circuit="c1", now_secs=102)
  assert_eq(cb_state(j3), "open")
  let j4 = e.circuit_status(ns="ns1", circuit="c1", now_secs=103)
  assert_eq(cb_state(j4), "open")
  let j5 = e.circuit_status(ns="ns1", circuit="c1", now_secs=132)
  assert_eq(cb_state(j5), "half_open")
  let j6 = e.circuit_succeed(ns="ns1", circuit="c1", now_secs=133)
  assert_eq(cb_state(j6), "closed")
}

///|
/// SQLite schema 与 fist-mbt 0.3.6 表级对齐：临时库建表后应为 16 张业务表，
/// tasks 表 17 列且列序与 fist-mbt.db 完全一致（含新补的 4 张骨架表）。
test "ops_sqlite_schema_table_parity" {
  let tmp = match @env.get_env_var("TEMP") {
    Some(s) => s
    None => "./"
  }
  let ms = @env.now().reinterpret_as_int64().to_string()
  let dbp = tmp + "\\mcpconftest_ops_test_" + ms + ".db"
  let s = match @lib.OpsSqliteStore::open(dbp) {
    Some(x) => x
    None => panic()
  }
  let db = match s.db {
    Some(d) => d
    None => panic()
  }
  let stmt = match db.prepare(
    "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  ) {
    Some(st) => st
    None => panic()
  }
  let n = if stmt.step() {
    Some(stmt.column_int(0))
  } else {
    None
  }
  stmt.finalize()
  match n {
    Some(cnt) => assert_eq(cnt, 16)
    None => panic()
  }
  let st2 = match db.prepare("PRAGMA table_info(tasks)") {
    Some(st) => st
    None => panic()
  }
  let mut cols : Array[String] = []
  while st2.step() {
    cols = cols + [@utf8.decode_lossy(st2.column_text(1))]
  }
  st2.finalize()
  assert_eq(cols.length(), 17)
  assert_eq(cols[0], "id")
  assert_eq(cols[16], "depends_on")
}
