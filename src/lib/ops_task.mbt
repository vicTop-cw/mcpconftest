///
/// ops_task.mbt —— mcpconftest 自实现任务模型与状态机（路线 A）。
/// 从 FIST-Mbt 的 @core.Task 语义逐字段对齐移植，移除对 fist-mbt 的包依赖：
/// 九态中文映射、Task 17 字段、纯函数状态迁移、child_id 生成均保持行为兼容。

///|
/// 任务九态状态机（与 FIST-Mbt @core.TaskStatus 完全一致）
pub enum TaskStatus {
  /// 待领取
  Pending
  /// 已领取
  Claimed
  /// 拆分中
  Splitting
  /// 执行中
  Executing
  /// 待验收
  Reviewing
  /// 已完成
  Completed
  /// 已归档
  Archived
  /// 已打回（验收不通过，需重做）
  Rejected
  /// 已暂停（外部中断/等待依赖）
  Paused
} derive(Eq, Debug)

///|
pub fn TaskStatus::to_string(self : TaskStatus) -> String {
  match self {
    Pending => "待领取"
    Claimed => "已领取"
    Splitting => "拆分中"
    Executing => "执行中"
    Reviewing => "待验收"
    Completed => "已完成"
    Archived => "已归档"
    Rejected => "已打回"
    Paused => "已暂停"
  }
}

///|
pub fn TaskStatus::from_string(s : String) -> TaskStatus? {
  match s {
    "待领取" => Some(Pending)
    "已领取" => Some(Claimed)
    "拆分中" => Some(Splitting)
    "执行中" => Some(Executing)
    "待验收" => Some(Reviewing)
    "已完成" => Some(Completed)
    "已归档" => Some(Archived)
    "已打回" => Some(Rejected)
    "已暂停" => Some(Paused)
    _ => None
  }
}

///|
pub fn TaskStatus::can_split(self : TaskStatus) -> Bool {
  match self {
    Pending | Claimed | Splitting | Rejected => true
    _ => false
  }
}

///|
pub fn TaskStatus::can_execute(self : TaskStatus) -> Bool {
  match self {
    Claimed | Splitting | Executing => true
    _ => false
  }
}

///|
pub fn TaskStatus::is_rejected(self : TaskStatus) -> Bool {
  self == Rejected
}

///|
pub fn TaskStatus::is_paused(self : TaskStatus) -> Bool {
  self == Paused
}

///|
pub fn TaskStatus::is_active(self : TaskStatus) -> Bool {
  match self {
    Pending | Claimed | Splitting | Executing | Reviewing => true
    _ => false
  }
}

///|
pub fn TaskStatus::is_completed(self : TaskStatus) -> Bool {
  self == Completed
}

///|
pub fn TaskStatus::is_pending(self : TaskStatus) -> Bool {
  self == Pending
}

///|
pub fn TaskStatus::is_claimed(self : TaskStatus) -> Bool {
  self == Claimed
}

///|
pub fn TaskStatus::is_splitting(self : TaskStatus) -> Bool {
  self == Splitting
}

///|
pub fn TaskStatus::is_executing(self : TaskStatus) -> Bool {
  self == Executing
}

///|
pub fn TaskStatus::is_reviewing(self : TaskStatus) -> Bool {
  self == Reviewing
}

///|
pub fn TaskStatus::is_archived(self : TaskStatus) -> Bool {
  self == Archived
}

///|
pub fn TaskStatus::order(self : TaskStatus) -> Int {
  match self {
    Pending => 0
    Claimed => 1
    Splitting => 2
    Executing => 3
    Reviewing => 4
    Completed => 5
    Archived => 6
    Rejected => 7
    Paused => 8
  }
}

///|
/// mcpconftest 自实现任务实体（与 FIST-Mbt @core.Task 字段逐一对齐）
pub struct Task {
  /// 形如 T0 / T0.1 / T0.1.2 的层级 id
  id : String
  parent_id : String?
  project_dir : String
  /// 命名空间（多租户隔离键，默认 "default"）
  ns : String
  priority : String
  importance : String
  /// K 值：根 3，每拆一层减 1；K<=1 为原子任务
  depth : Int
  /// 拆分数量（默认 3）
  split_n : Int
  status : TaskStatus
  assignee : String?
  description : String
  deliverable : String
  created_at : String
  updated_at : String
  completed_by : String?
  cleanup_mode : String
  /// 依赖的任务 id 列表（这些任务完成后，本任务才可领取）
  depends_on : Array[String]
} derive(Eq, Debug)

///|
pub fn Task::status_to_string(self : Task) -> String {
  self.status.to_string()
}

///|
pub fn Task::get_id(self : Task) -> String {
  self.id
}

///|
pub fn Task::get_parent(self : Task) -> String? {
  self.parent_id
}

///|
pub fn Task::get_status(self : Task) -> TaskStatus {
  self.status
}

///|
pub fn Task::get_depth(self : Task) -> Int {
  self.depth
}

///|
pub fn Task::get_split_n(self : Task) -> Int {
  self.split_n
}

///|
pub fn Task::get_description(self : Task) -> String {
  self.description
}

///|
pub fn Task::get_assignee(self : Task) -> String? {
  self.assignee
}

///|
pub fn Task::get_updated_at(self : Task) -> String {
  self.updated_at
}

///|
pub fn Task::get_project_dir(self : Task) -> String {
  self.project_dir
}

///|
pub fn Task::get_ns(self : Task) -> String {
  self.ns
}

///|
pub fn Task::get_deliverable(self : Task) -> String {
  self.deliverable
}

///|
pub fn Task::is_leaf(self : Task) -> Bool {
  self.depth <= 1
}

///|
/// 构造器（字段带默认值，与 FIST-Mbt Task::new 对齐）
pub fn Task::new(
  id~ : String,
  project_dir~ : String,
  description? : String = "",
  priority? : String = "中",
  importance? : String = "中",
  depth? : Int = 3,
  split_n? : Int = 3,
  parent_id? : String = "",
  assignee? : String = "",
  cleanup_mode? : String = "deferred",
  created_at? : String = "",
  ns? : String = "default",
  depends_on? : Array[String] = [],
) -> Task {
  {
    id,
    parent_id: if parent_id == "" {
      None
    } else {
      Some(parent_id)
    },
    project_dir,
    ns,
    priority,
    importance,
    depth,
    split_n,
    status: Pending,
    assignee: if assignee == "" {
      None
    } else {
      Some(assignee)
    },
    description,
    deliverable: "",
    created_at,
    updated_at: created_at,
    completed_by: None,
    cleanup_mode,
    depends_on,
  }
}

///|
/// 按存储行字段直接构建任务（供 store 层反序列化使用；status 为存储字符串，非法回退 Pending）
pub fn Task::from_db(
  id : String,
  parent_id : String?,
  project_dir : String,
  ns : String,
  priority : String,
  importance : String,
  depth : Int,
  split_n : Int,
  status_s : String,
  assignee : String?,
  description : String,
  deliverable : String,
  created_at : String,
  updated_at : String,
  completed_by : String?,
  cleanup_mode : String,
  depends_on : Array[String],
) -> Task {
  let status = match TaskStatus::from_string(status_s) {
    Some(s) => s
    None => Pending
  }
  {
    id,
    parent_id,
    project_dir,
    ns,
    priority,
    importance,
    depth,
    split_n,
    status,
    assignee,
    description,
    deliverable,
    created_at,
    updated_at,
    completed_by,
    cleanup_mode,
    depends_on,
  }
}

/// —— 状态迁移 ——
/// 每个迁移都是纯函数（返回新 Task），状态机非法流转直接拒绝。
/// 返回 Err(msg) 表示非法迁移。

///|
/// 待领取 -> 已领取（角色：any active agent）
pub fn Task::claim(self : Task, assignee~ : String) -> Result[Task, String] {
  match self.status {
    Pending =>
      if assignee == "" {
        Err("claim 需要 assignee")
      } else {
        Ok({ ..self, status: Claimed, assignee: Some(assignee), })
      }
    _ =>
      Err(
        "非法迁移: claim 要求状态 [待领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已领取 -> 拆分中（指挥官拆解）
pub fn Task::split(self : Task) -> Result[Task, String] {
  match self.status {
    Claimed =>
      if self.is_leaf() {
        Err("原子任务(K<=1)不可再拆分")
      } else {
        Ok({ ..self, status: Splitting, })
      }
    _ =>
      Err(
        "非法迁移: split 要求状态 [已领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 拆分中标记（AO 式拆解用，宽于 split：待领取/已领取/拆分中均可转入）
pub fn Task::mark_decomposing(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting => Ok({ ..self, status: Splitting, })
    _ => Err("非法拆解: 任务处于 [\{self.status.to_string()}]")
  }
}

///|
/// 拆分中/已领取/执行中 -> 执行中（进入/覆盖/追加交付物）
pub fn Task::execute(self : Task) -> Result[Task, String] {
  match self.status {
    Splitting | Claimed | Executing => Ok({ ..self, status: Executing, })
    _ =>
      Err(
        "非法迁移: execute 要求状态 [拆分中/已领取/执行中]，当前是 [" +
        self.status.to_string() +
        "]。出路：" +
        Task::execute_exit_hint(self.status),
      )
  }
}

///|
/// execute 被拒时按当前状态给出可用出路（纯函数便于回归测试）
pub fn Task::execute_exit_hint(status : TaskStatus) -> String {
  match status {
    Pending => "待领取→先 claim 再 execute"
    Claimed | Splitting | Executing => "已是可执行状态，直接 execute"
    Rejected =>
      "已打回→先 retry（→执行中）再 execute 覆盖交付物"
    Reviewing =>
      "待验收→若要改交付物先 reject（→已打回）再 retry（→执行中），再 execute"
    Paused => "已暂停→先 resume（→已领取）再 execute"
    Completed =>
      "已完成→原地更正交付物请 reopen_task（→待领取）后重新走链路，勿新建任务覆盖旧账"
    Archived =>
      "已归档→不可写；确需返工先 reopen_task 重开，勿新建任务覆盖旧账"
  }
}

///|
/// 执行中 -> 待验收
pub fn Task::submit(self : Task) -> Result[Task, String] {
  match self.status {
    Executing => Ok({ ..self, status: Reviewing, })
    _ =>
      Err(
        "非法迁移: submit 要求状态 [执行中]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 待验收 -> 已完成（人类主权：completed_by 必须非空）
pub fn Task::complete(
  self : Task,
  completed_by~ : String,
) -> Result[Task, String] {
  match self.status {
    Reviewing =>
      if completed_by == "" {
        Err("complete 需要 completed_by 身份")
      } else {
        Ok({ ..self, status: Completed, completed_by: Some(completed_by), })
      }
    _ =>
      Err(
        "非法迁移: complete 要求状态 [待验收]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已完成 -> 已归档
pub fn Task::archive(self : Task) -> Result[Task, String] {
  match self.status {
    Completed => Ok({ ..self, status: Archived, })
    _ =>
      Err(
        "非法迁移: archive 要求状态 [已完成]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 任意非归档状态 -> 已领取（被打回重做）
pub fn Task::reopen(self : Task) -> Result[Task, String] {
  match self.status {
    Archived => Err("已归档任务不可 reopen，请重新发布")
    Rejected =>
      Ok({ ..self, status: Claimed, assignee: None, deliverable: "", })
    Paused => Ok({ ..self, status: Claimed, })
    _ => Ok({ ..self, status: Claimed, })
  }
}

///|
/// 待验收 -> 已打回（验收不通过，需重做）
pub fn Task::reject(self : Task, reason? : String = "") -> Result[Task, String] {
  match self.status {
    Reviewing =>
      Ok({
        ..self,
        status: Rejected,
        description: if reason == "" {
          self.description
        } else {
          self.description + " [打回原因: " + reason + "]"
        },
      })
    _ =>
      Err(
        "非法迁移: reject 要求状态 [待验收]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已打回 -> 执行中（重新执行）
pub fn Task::retry(self : Task) -> Result[Task, String] {
  match self.status {
    Rejected => Ok({ ..self, status: Executing, })
    _ =>
      Err(
        "非法迁移: retry 要求状态 [已打回]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 任意活跃状态 -> 已暂停（外部中断/等待依赖）
pub fn Task::pause(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting | Executing | Reviewing | Rejected =>
      Ok({ ..self, status: Paused, })
    Paused => Err("任务已处于暂停状态")
    _ =>
      Err(
        "非法迁移: pause 要求活跃状态，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已暂停 -> 已领取（恢复执行）
pub fn Task::resume_task(self : Task) -> Result[Task, String] {
  match self.status {
    Paused => Ok({ ..self, status: Claimed, })
    _ =>
      Err(
        "非法迁移: resume_task 要求状态 [已暂停]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 记录类复制更新
pub fn Task::with_updated_at(self : Task, now : String) -> Task {
  { ..self, updated_at: now, }
}

///|
pub fn Task::with_deliverable(
  self : Task,
  deliverable : String,
  now : String,
) -> Task {
  { ..self, deliverable, updated_at: now, }
}

///|
/// 追加一条前置依赖（去重）并更新时间戳
pub fn Task::with_depends_on(
  self : Task,
  dep_id : String,
  now : String,
) -> Task {
  let deps : Array[String] = if self.depends_on.contains(dep_id) {
    self.depends_on
  } else {
    let out : Array[String] = []
    for d in self.depends_on {
      out.push(d)
    }
    out.push(dep_id)
    out
  }
  { ..self, depends_on: deps, updated_at: now, }
}

///|
/// 生成子任务 id：T0.1.2 -> T0.1.2.1
pub fn child_id(parent_id~ : String, idx~ : Int) -> String {
  "\{parent_id}.\{idx}"
}
