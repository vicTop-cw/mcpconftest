# 规则演进流程（Rule Lifecycle）

> 对齐 sigmaLang 一致性门禁：新增/修改检查项必须走完整闭环，缺一步 CI 即红。

## 新增检查项

1. **写规格**：`scripts/new-check.ps1 -Id <check_id> -Category <category> -Title "<title>"`，
   生成 `specs/<category>/<name>/spec.json` + `README.md`（L1 规格即真源）。
   - 规格必须声明 operations / preconditions / laws / backends
   - 生成后自动计算并写入确定性 `fingerprint`（sha256，L4 无指纹不发布）
2. **加语料**：在 `corpus/<check_id>/pass/` 放至少 1 个合规样例、
   `corpus/<check_id>/fail/` 放至少 1 个违规样例（L3 有规必有语料）。
3. **双端实现**：在 `src/lib/checks.mbt` 实现检查逻辑；js 与 native 后端必须行为一致（L2 双端共识）。
4. **装配验证**：重新构建后跑 `scripts/verify-specs.ps1` 与双后端 diff，CI 全绿。
5. **提交**：修改既有规格语义 → bump 版本号 + CHANGELOG "破坏性变更" 示警（L5）。

## 修改既有检查项

- 仅改文案/描述：更新规格与指纹，小版本 bump。
- 改语义（operations / preconditions / laws 变化）：视为破坏性变更，主/次版本 bump + CHANGELOG 示警。
- 删除检查项：必须先在 CHANGELOG 示警并保留一个版本周期的迁移说明。

## 门禁速查

| 步骤 | 命令 |
|---|---|
| L1 规格即真源 | `powershell -File scripts/verify-specs.ps1` |
| L2 双端共识 | `moon test` + 双 target 结果 diff（scripts/ci.sh） |
| L3 有规必有语料 | `scripts/verify-corpus.ps1`（覆盖率 ≥ 60%，发布前 ≥ 80%） |
| L4 无指纹不发布 | 发布前校验 specs/**/spec.json 均含 sha256 fingerprint |
| L5 破坏性变更示警 | tag 间 spec diff 人工复核 |
