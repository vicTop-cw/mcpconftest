---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_c38ec835cbde11f1b307525400393706
    ReservedCode1: QZdcZq9DCh+0ylg1vFRC96julOc7pjp69NcpEW9yCQA4Rhz0KS8dloucXGq2AMpkgMPpTl0HHsD0KlGWh1Cezz2l0BM2gQqBIgsHoqOx2cfL8l1kZpErINpvQPfC+Ri7ixrXq6uK0k32HVGeNN2jTFDp0Zf80rh2gr8mHuZ+VTytjc346hCobLNbK8g=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_c38ec835cbde11f1b307525400393706
    ReservedCode2: QZdcZq9DCh+0ylg1vFRC96julOc7pjp69NcpEW9yCQA4Rhz0KS8dloucXGq2AMpkgMPpTl0HHsD0KlGWh1Cezz2l0BM2gQqBIgsHoqOx2cfL8l1kZpErINpvQPfC+Ri7ixrXq6uK0k32HVGeNN2jTFDp0Zf80rh2gr8mHuZ+VTytjc346hCobLNbK8g=
---

# mcpconftest 变更日志

## 0.9.0 (2026-10-19)

- 实施自研铁律阶段0：新增 `docs/IRON-LAWS.md`（R1-R6 规格化：定义/判定规则/自检命令/违反后果）与 `scripts/verify-iron-laws.ps1`（一键自检骨架）。
- R1：`CheckResult` 新增 `skip_reason` / `hard` 字段与 `hard_fail` / `soft_fail` / `skip_with_reason` 构造函数（旧 `fail` / `skip` 保留兼容）。
- R2：新增 `specs_fingerprint()`（specs 树指纹 SHA-256），`Report.spec_fingerprint` 字段在 `build_report` 填充，JSON/Markdown/HTML 报告输出指纹头。
- R6：`Report.verdict()`（hard Fail → fail；Skip 无原因 → inconclusive；否则 pass），JSON/MD/HTML 输出 verdict；CLI `run` 结束打印 `VERDICT` 且非 pass 退出码非 0。
- 报告 schema 变更（验证行为变更），按 VERSIONING.md MINOR +1。

## 0.9.0 补丁 (2026-10-23)

初审打磨：上次 MoonBit 赛事/项目申报初审被驳回，本轮全量修复四个驳回点。

- **R1 skip 标注修复**（P0）：`src/lib/checks.mbt` 中 20 处 `CheckResult::skip(name, msg)` 旧构造函数（强制 `skip_reason=""`，导致报告显示 "NO REASON"）全部改为 `skip_with_reason(name, msg, reason)`。fixture 实跑验证 5 个 skip 全部带 skip_reason，不再违反 SKIP_WITH_REASON 铁律。
- **门禁全量接通**：`scripts/verify-fixture.ps1` 增强 R1 skip_reason 非空检查（原仅检查计数，不验证 skip 原因）；`scripts/verify-iron-laws.ps1` 注释从"阶段0骨架"校准为"全量门禁已接通"。`verify-iron-laws.ps1` 实测 ALL PASS 7/7（L0-L6：文档完整性 + R2 指纹实算 + R3 双向闭合 170 mapped/7 internal + R5 fixture diff 含 skip_reason 校验）。
- **申报书/文档校准 v0.9.0**：`项目申报书.md` 全面更新——铁律 R1-R6 实施证据、`moon test` 15→20、FIST-Mbt 依赖过时修正（路线 A 已自实现 OpsEngine，移除 fist-mbt 依赖）、§11 结论补铁律门禁 ALL PASS 证据；`README.md` / `docs/INSTALL.md` / `docs/checklist.md` 版本号校准 v0.9.0，消除 v0.6/v0.7.0 过时引用。
- **moonfmt 格式化**：`src/lib/specs.mbt` 经 moon 0.1.20261016 工具链 moonfmt 重新格式化（文档注释换行 + 调用换行），无功能变更。
- 全量自检复跑全绿：`moon check` js/native 0 errors、`moon test` 20/20 双后端、`verify-iron-laws.ps1` ALL PASS 7/7、fixture 38/58 ALL GREEN、e2e ALL GREEN。
*（内容由AI生成，仅供参考）*
