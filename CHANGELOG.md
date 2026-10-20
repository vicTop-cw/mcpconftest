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
*（内容由AI生成，仅供参考）*
