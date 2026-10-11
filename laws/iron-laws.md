# mcpconftest Iron Laws

> 本库自身的元规范（对齐 sigmaLang 铁律精神，面向 MCP 协议合规域）。
> 每条铁律对应 CI 硬门，违反即红。

| 铁律 | 含义 | 强制手段 |
|---|---|---|
| L1 规格即真源 | 检查项必须从 specs/ 生成，禁止代码内注册 | CI 比对 list-checks 输出与 specs/ 目录 |
| L2 双端共识 | js 与 native 后端对同一检查项结果必须一致 | CI 跑双后端 diff，不一致即红 |
| L3 有规必有语料 | 每新增检查项必须附带合规+违规 corpus 用例 | 覆盖率门禁 |
| L4 无指纹不发布 | 每个检查项必须含确定性 fingerprint | 发布前门禁 |
| L5 破坏性变更必示警 | 修改既有检查项语义必须 bump 版本并在 CHANGELOG 示警 | 人工复核项 |

## 铁律细则

### L1 规格即真源

- `specs/` 是检查项的唯一事实来源，每个检查项一个子目录：
  `specs/<category>/<check_id>/`，内含 `spec.json`（机读）与 `README.md`（人读）。
- 引擎启动时读 `specs/**/spec.json` 动态装配；`list-checks` 输出必须与 specs/ 目录一致。
- 禁止在代码中新增未登记的检查项；CI 用脚本比对（scripts/verify-specs.sh 或 .ps1）。

### L2 双端共识

- js 与 native 后端对同一检查项、同一输入必须输出一致结果（pass/fail/err 分布一致）。
- CI 对全部 corpus 用例跑双后端 diff，不一致即红。
- 规范不一致时以 spec 定义为准，双端实现向 spec 对齐。

### L3 有规必有语料

- 每个检查项必须至少 1 个合规用例（corpus/<check_id>/pass/*.json）与 1 个违规用例
  （corpus/<check_id>/fail/*.json）。
- CI 统计 corpus 覆盖率：新增检查项无语料即红；发布前总覆盖率 ≥ 80%。

### L4 无指纹不发布

- 每个 spec.json 必须含 `fingerprint` 字段（sha256 确定性指纹，由规格字段序列化计算）。
- 发布前门禁校验：spec 变更 → fingerprint 必须同步更新；缺失即红。

### L5 破坏性变更必示警

- 修改既有检查项的语义（operations / preconditions / laws 变更）视为破坏性变更：
  必须 bump 主/次版本号，并在 CHANGELOG 记录"破坏性变更"条目。
- 由 CI 比对 tag 间 spec 差异给出提示，最终人工复核。

## 规则演进流程

新增规则 = 写 spec + corpus 加语料 + 双后端实现 + CI 门禁通过。
详见 docs/rule-lifecycle.md。
