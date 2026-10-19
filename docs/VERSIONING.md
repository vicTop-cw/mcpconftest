---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_9439246fcb6811f196f9525400248c00
    ReservedCode1: UfPEaPgeCW8ZhtDVaxWsrZJDsNxIbgXRqTgNqDoU0YkYU1QiV4q5fFk4qzMKq6WLlkBzTEEBtVyyJb4kHGYM6IS23fsMC4JClqyPX0qyySiGVrLUsrw0ZPWCdsgk6Eqs9F+mK7eqIbiJdKvdr20TsM3lpWSe6NvIYmCv3sWBZk1btsk0GD/fV6Y5pes=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_9439246fcb6811f196f9525400248c00
    ReservedCode2: UfPEaPgeCW8ZhtDVaxWsrZJDsNxIbgXRqTgNqDoU0YkYU1QiV4q5fFk4qzMKq6WLlkBzTEEBtVyyJb4kHGYM6IS23fsMC4JClqyPX0qyySiGVrLUsrw0ZPWCdsgk6Eqs9F+mK7eqIbiJdKvdr20TsM3lpWSe6NvIYmCv3sWBZk1btsk0GD/fV6Y5pes=
---

# mcpconftest 版本与发布细则（VERSIONING）

> 目标：GitHub 与 mooncakes 版本统一；mooncakes 只发 `x.y.0`；验证行为变更必发新版。
> 配套：`docs/rule-lifecycle.md`（规则生命周期 / L1-L5 闸门）。

## 1. 核心约定

| 约定 | 内容 |
|---|---|
| 事实源 | `moon.mod` 的 `version` 字段是唯一版本事实源 |
| 版本格式 | 语义化版本 2.0.0，完整三位 `MAJOR.MINOR.PATCH` |
| 本仓库发布策略 | 发布版本固定为 `x.y.0`（PATCH 恒为 0），递增走 MINOR +1（0.8.0 → 0.9.0 → 0.10.0） |
| 三处对齐 | `moon.mod version` ↔ GitHub tag（`vx.y.0`）↔ mooncakes 发布（`x.y.0`），一次发布三处同一版本号 |
| 单调递增 | 每次发布版本号必须大于上一发布（mooncakes 强制校验）；GitHub tag 同规则 |
| 验证变更必发 | 任何影响「验证行为 / 验证结果」的变更，必须 bump MINOR 并发布新版 mooncakes + GitHub tag |

说明：mooncakes 平台本身接受完整 SemVer `x.y.z`（PATCH 合法）；`x.y.0` 是本仓库的自定策略，避免 PATCH 位发布带来三端口径混乱。

## 2. 变更分类与发布义务

| 变更类型 | 示例 | 推 GitHub | 发 mooncakes |
|---|---|---|---|
| 验证行为变更 | `specs/**/spec.json`、`laws/`、`corpus/`、`src/` 判定与报告逻辑、check 清单、协议支持范围 | 必推 + 打 tag | 必发新版 |
| 破坏性 API 变更 | 公开接口不兼容 | MAJOR +1，必推 | 必发 |
| 向后兼容新功能 | 新增 check 类别 / 报告格式 | MINOR +1，必推 | 必发 |
| 非验证变更 | README、CI、纯文档、注释 | 可推（不打 tag 或随版） | 不必单独发，并入最近一次发布 |

## 3. 版本号位置清单（一处变更必须全部同步）

| 位置 | 格式 | 示例 |
|---|---|---|
| `moon.mod` version | 无前缀 | `0.9.0` |
| GitHub tag | `v` 前缀 | `v0.9.0` |
| mooncakes 发布版本 | 无前缀 | `0.9.0` |
| `moon.mod` repository | 真实仓库 URL | `https://github.com/vicTop-cw/mcpconftest` |
| CHANGELOG | 每版一条 | `## 0.9.0 (2026-xx-xx)` |

## 4. 发布流程

1. 收口工作区：所有改动 commit 到 `main`。
2. 更新 `moon.mod` 的 `version = "x.y.0"`，更新 CHANGELOG。
3. 本地全闸门：`moon check`、`moon test`、`scripts/ci.sh`（js/native 双 target）、`scripts/verify-specs.ps1`、`scripts/verify-corpus.ps1` 全绿。
4. 打 tag：`git tag vx.y.0`，推送所有远程（GitHub 必须其一）。
5. 发布：`moon publish`（mooncakes 校验单调递增）。
6. 复核：mooncakes 页面版本 == GitHub tag == moon.mod。

## 5. 当前状态核对（2026-10-19）

| 端 | 状态 | 缺口 |
|---|---|---|
| GitHub tag | v0.2.0 / v0.3.0 / v0.4.0 / v0.5.0 | 缺 v0.6.0 / v0.7.1 / v0.8.0（v0.7.0 亦未打） |
| mooncakes | 0.6.0 / 0.7.0 / 0.7.1 / 0.8.0 | 与 GitHub 不对齐；0.7.0 / 0.7.1 违反 x.y.0 约定（历史遗留） |
| 本地 moon.mod | 0.8.0 | 与 mooncakes 最新一致 |
| 本地 remote | gitcode + atomgit | 缺 GitHub remote |
| moon.mod repository | `https://github.com/VictorTop/mcpconftest` | 大小写错误，应为 `vicTop-cw/mcpconftest` |
| 工作区 | 有未提交修改 + untracked | 发布前必须收口 |

## 6. 历史例外

- 0.7.1（PATCH 非 0）已发布 mooncakes，属历史遗留，不追溯；新规则自下一版本（0.9.0）起执行。
- `v0.8.1-baseline` 是内部基线冻结 tag，不代表发布版本，不推 GitHub、不发 mooncakes。
- `v0.7.0` 仅在 mooncakes 存在（本地与 GitHub 均未打 tag）：按「一次发布三处对齐」原则，若需保留需补 tag，否则忽略。

## 7. 待确认 / 下一步

- [ ] 补齐 GitHub 远程并推送已有 tag（v0.6.0 / v0.7.1 / v0.8.0）
- [ ] 修正 moon.mod repository 字段大小写
- [ ] 收口工作区未提交修改
- [ ] 下一次发布按新规则：验证变更 → bump 0.9.0 → 三处同步
*（内容由AI生成，仅供参考）*
