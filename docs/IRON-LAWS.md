# mcpconftest 自研铁律（IRON LAWS）

> 版本：v1.0
> 日期：2026-10-19
> 定位：mcpconftest 是给 AI 用的协议合规验证工具，人类一般不直接看产物。因此"明面铁律"必须机器可执行、AI 可读、可自证；人类信任靠机器自证而非文档。

本文件是 mcpconftest 的**合规判定依据**。任何检查、报告、发布行为都必须服从以下六条铁律。每条铁律包含：**定义 / 判定规则 / 自检命令 / 违反后果**。

---

## R1 — 失败三分（HARD / SOFT / SKIP_WITH_REASON）

**定义**：检查结果不允许模糊的 "fail / skip"。失败必须分硬违（HARD）与软违（SOFT）；跳过必须带原因（SKIP_WITH_REASON），无原因的跳过是无效结果。

**判定规则**：
- HARD：`CheckResult.hard = true`，表示规格强制要求的性质被违反，必须阻断 pass verdict。
- SOFT：`CheckResult.hard = false`，表示非强制的建议性偏差，计入统计但不阻断 pass verdict。
- SKIP：`CheckResult.skip_reason` 非空才有效；为空视为无效跳过，verdict 判 inconclusive。
- 旧构造 `CheckResult::fail` / `CheckResult::skip` 保留兼容但已标记 deprecated；新代码一律使用 `hard_fail` / `soft_fail` / `skip_with_reason`。

**自检命令**：
- `moon test src/lib --target js && moon test src/lib --target native`（types_test.mbt 覆盖三态构造与 verdict 分类）
- `grep -rn "hard_fail\|soft_fail\|skip_with_reason" src/lib`（新代码使用三态构造）

**违反后果**：报告 verdict 失真——存在 HARD 或无效 SKIP 仍输出 pass，属发布阻断缺陷（P0）。

---

## R2 — 规格即判据（报告必须携带规格联合指纹）

**定义**：任何报告必须声明"本次判定依据的规格版本"。判定依据 = 规格树联合指纹 + 协议版本。指纹缺失的报告是无效报告。

**判定规则**：
- `specs_fingerprint()` 遍历 `specs/**/spec.json` 的 `fingerprint` 字段，按 `check_id` 排序后拼接 `check_id=fingerprint\n`，整体做 SHA-256，输出 `sha256:<hex>`。
- `Report.spec_fingerprint` 由 `build_report` 自动填充；无法读取规格树时输出空串，且该报告不可作为"合规通过"依据。
- JSON / Markdown / HTML 三端必须输出 `spec_fingerprint` 头；JUnit 头注释携带。

**自检命令**：
- `moon run cmd -- run --fixture --report ./mcpconftest-report && grep spec_fingerprint ./mcpconftest-report/report.json`

**违反后果**：报告无法复核"是哪版规格判的"，AI 篡改检查逻辑后旧报告无法追溯——合规判定依据混淆（赛事驳回点），发布阻断（P0）。

---

## R3 — 实现不得超出规格（实现 ↔ 规格双向闭合）

**定义**：检查实现中引用的每条检查项（check_id）必须能在 `specs/**/spec.json` 中找到；规格里没有的判定 = 违规实现。反向：规格中每一条 spec.json 的 check_id 都必须在检查实现中有注册引用（存在性扫描 + 人工复核清单）。

**判定规则**：
- 静态扫描 `src/lib/checks.mbt`、`src/lib/fist_ops.mbt` 中形如 `mcp.*` / `mcpcf.*` 的 check_id 字面量，逐一验证 specs 目录下存在对应 spec.json。
- 反向校验 specs 全部 spec.json 的 check_id 均有代码引用；无法静态命中的动态拼接项列入人工复核清单。
- 任一缺失项 = 校验红。

**自检命令**：
- `pwsh ./scripts/verify-specs.ps1`（实现 ↩ 规格双向闭合扫描）

**违反后果**：检查项与规格脱节，可能出现"规格没有的判定"或"规格要求的检查没实现"，合规结论不可信（P0）。

---

## R4 — 改一验三（发布前置三重门禁）

**定义**：检查项变更必须同时通过三扇门，缺一即发布红：
1. 双端测试全绿（js + native）；
2. 新旧 spec 指纹 diff 留痕（`specs_fingerprint` 变化可审计）；
3. 语料正反例齐全（corpus 覆盖率达标，发布 ≥80%）。

**判定规则**：
- 发布 job 先跑 `moon test` js/native → `verify-specs.ps1`（含 R3）→ `verify-corpus.ps1`（≥80%）→ fixture 快照 diff；任一失败即红。
- 指纹变化必须伴随显式说明（提交信息或变更记录）。

**自检命令**：
- `pwsh ./scripts/ci.sh`（或 CI：GitHub Actions `iron-laws` job / GitCode 工作流）

**违反后果**：未经三验的检查项变更直接发布，规格漂移与回归风险无人为可控（P0）。

---

## R5 — 验证器被验证（fixture 预期快照）

**定义**：mcpconftest 自身的 fixture 自检结果必须与预期快照一致。预期数变化必须显式声明（提交快照变更），禁止静默漂移。

**判定规则**：
- fixture 实跑结果（pass/fail/skip/warn 计数与关键检查项名单）与 `scripts/fixture-expected.json` diff，不一致即红。
- 确需改变预期时，必须显式提交快照变更，人工可审。

**自检命令**：
- `pwsh ./scripts/verify-iron-laws.ps1 --fixture`（fixture 快照 diff，阶段 3 充实）
- 当前基线：fixture 38/58 pass、15 fail、5 skip（阶段 1 后以实测快照为准）

**违反后果**：验证器自身回归而无人察觉，工具从"合规验证器"退化为"输出生成器"（P0）。

---

## R6 — <100% 不标记完成（强制 verdict 闸门）

**定义**：结论必须三态：`pass` / `fail` / `inconclusive`。存在 HARD 失败或无理由 SKIP 时，绝不输出 pass。

**判定规则**：
- `Report::verdict()`：存在 `hard=true` 的 Fail → `"fail"`；否则存在 Skip 且 `skip_reason` 为空 → `"inconclusive"`；否则 → `"pass"`。
- JSON / MD 报告输出 `verdict` 字段；CLI `run` 结束打印 `VERDICT: <pass|fail|inconclusive>`。
- verdict != `pass` 时 CLI 退出码非 0（`cli_exit(1)`）。

**自检命令**：
- `moon run cmd -- run --fixture --report ./mcpconftest-report; echo $LASTEXITCODE`（fixture 含硬违 → VERDICT: fail、退出码 1）
- `grep verdict ./mcpconftest-report/report.json`

**违反后果**：存在硬违或无理由 skip 仍输出"通过"，AI 将不合格协议判为合规——信任崩塌（P0）。

---

## 自检命令总览（一键自检）

```powershell
pwsh ./scripts/verify-iron-laws.ps1
```

阶段 0 的 verify-iron-laws.ps1 骨架覆盖：本文件存在性与六条铁律完整性、每条铁律的自检命令可解析、specs 规格树存在、R2 指纹预检（报告含 spec_fingerprint）。阶段 1-3 逐步充实为全量门禁（R3/R4/R5 接入）。

## 版本与维护

- 铁律变更本身必须走评审：修改本文需同时更新 `scripts/verify-iron-laws.ps1` 与发布门禁，任何一条铁律不可在无自检命令的情况下存在。
- 本文 v1.0 对应实施计划 v1.0（2026-10-19 用户批准）。
