---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_5f9408f2c3ec11f19063525400393706
    ReservedCode1: I5UPre87o9HkyKLJyWmjyFfiLygb/bRFEHXx9sQCYa2wciz/ySG4c5ez+6Bn3Q29S2yfgI7KjKZFpsF/ZFOUyaLSTfSodBxqGZDh3SVkIGSlkHvhPlc8rvDTU9BQ/HqgbvvUd/ziCLFWsuleB7Aw/tAJR7QzWjGmrPrJuV5kmcWuzG2HEn3SoIXgxyk=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_5f9408f2c3ec11f19063525400393706
    ReservedCode2: I5UPre87o9HkyKLJyWmjyFfiLygb/bRFEHXx9sQCYa2wciz/ySG4c5ez+6Bn3Q29S2yfgI7KjKZFpsF/ZFOUyaLSTfSodBxqGZDh3SVkIGSlkHvhPlc8rvDTU9BQ/HqgbvvUd/ziCLFWsuleB7Aw/tAJR7QzWjGmrPrJuV5kmcWuzG2HEn3SoIXgxyk=
---

# mcpconftest 安装与注册指南（一行命令）

mcpconftest 采用与 **FIST-Mbt** 同款的一行命令安装注册体系：
`scripts/blackbox/` 下的安装器负责下载发行资产（`mcpconftest-js-v<版本>.zip`）、
解压安装、创建命令 shim、注册用户级 PATH，并在末尾自检——自检通过即输出
**《mcpconftest 命令已注册》**。

## 快速开始（一行命令）

### Windows（PowerShell）

首选（GitHub 镜像仓库 raw 直链；仓库未推送时请用下方"本地/离线"入口）：

```powershell
iex ((irm https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
```

备用（GitCode 镜像；该域匿名 raw 实测返回 HTML 页，可能无法直接 iex）：

```powershell
irm https://gitcode.com/VictorTop/mcpconftest/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
```

### Linux / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install.sh | bash
```

### 本地 / 离线（不发 Release 也能装，发布前自证推荐）

先用打包脚本产出 zip：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\blackbox\release_zip.ps1
```

再本地安装：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\blackbox\install_onecmd.ps1 -Version 0.9.0 -LocalZip _release\mcpconftest-js-v0.8.0.zip
```

```bash
MCP_LOCAL_ZIP=_release/mcpconftest-js-v0.8.0.zip bash scripts/blackbox/install.sh
```

## 安装后

```bash
mcpconftest version        # mcpconftest v0.9.0
mcpconftest list-checks    # 列出全部检查类别
mcpconftest run --fixture  # 对内建 fixture 全量探测（38/58 pass, 15 fail 为预期违规）
mcpconftest serve          # 以 MCP server 形态启动（stdio），暴露 version / run_probe / list_checks 三个工具
```

安装位置与注册项：

| 项 | 位置 |
|---|---|
| 程序（Windows） | `%LOCALAPPDATA%\mcpconftest\mcpconftest.js` |
| 程序（Linux） | `~/.local/share/mcpconftest/mcpconftest.js` |
| 命令 shim | `%USERPROFILE%\.local\bin\mcpconftest[.cmd|-mbt[.cmd]]`（Windows）<br>`~/.local/bin/mcpconftest[-mbt]`（Linux） |
| PATH 注册 | Windows：用户级 PATH 追加 `.local\bin`；Linux：shell rc 追加 `.local/bin` |

shim 共四件：`mcpconftest.cmd` / `mcpconftest-mbt.cmd`（cmd 侧）与
`mcpconftest` / `mcpconftest-mbt`（POSIX 无扩展名、LF 行尾，供 Git Bash / MSYS / WSL 使用）。

## 安装器参数

### Windows（install_onecmd.ps1）

| 参数 | 说明 |
|---|---|
| `-Version <v>` | 显式指定版本（缺省按序解析：zip 文件名 → 远端 moon.mod → 内嵌默认值） |
| `-Force` | 覆盖已存在的安装目录 |
| `-LocalZip <path>` | 用本地 zip 安装（跳过下载；离线 / 发布前自证） |
| `-BaseUrl <url>` | 镜像入口（内网镜像 / 本机 http.server），按公网同形路径取 moon.mod 与资产 |

### Linux（install.sh）

| 变量 / 参数 | 说明 |
|---|---|
| `MCP_VERSION=<v>` 或首个非 flag 参数 | 显式指定版本 |
| `--force` | 覆盖已存在的安装目录 |
| `MCP_LOCAL_ZIP=<path>` | 用本地 zip 安装（跳过下载） |
| `MCP_BASE_URL=<url>` | 镜像入口（与 `MCP_LOCAL_ZIP` 互斥） |

## 版本解析与下载源

- 版本号唯一真源 = `moon.mod` 的 `version` 字段（发行资产名也由它生成）。
- 版本解析顺序：`-Version` / `MCP_VERSION` → 本地 zip 文件名 → 远端 `moon.mod`
  （GitHub raw → GitCode raw → AtomGit raw，逐源 HTML sniff 防护）→ 内嵌默认值。
- 下载源：GitCode Release Assets 直链（首选）→ AtomGit Release Assets 直链（备用）。
  带 PK 魔数与体积双重校验，传输层失败自动 curl 换栈重试。

## 双后端

安装器分发 **JS 后端**（Node ≥18，推荐 22+ 原生 WebSocket），一条命令即可用。

**native 后端**（Linux / Windows 原生可执行）由仓库源码构建：

```bash
moon build --target native --release
# 产物：_build/native/release/build/cmd/cmd.exe（Windows）/ cmd（Linux）
```

`src/lib` 已配置 `supported_targets = "js+native"`，两后端共享同一套 CLI 与 MCP 逻辑。

## MCP 化（库即 MCP server）

`mcpconftest serve` 以 MCP server 形态启动（stdio 传输），向客户端暴露三个工具：

| 工具 | 作用 |
|---|---|
| `version` | 报告 mcpconftest 版本 |
| `run_probe` | 对指定 MCP server 执行协议合规探测（参数：servers / report_dir / junit） |
| `list_checks` | 列出全部检查类别 |

按 2026-07-28 无状态协议实现：initialize 被正确移除（返回 -32601），
tools/list 正常分发。任何支持 stdio MCP 的客户端可直接拉起：

```bash
# 例如 Claude Code / Cursor / 自研 MCP 客户端的配置
mcpconftest serve
```

## 验收样例：《fist-mbt 命令已注册》

FIST-Mbt 项目采用同一套 `scripts/blackbox` 安装注册体系，作为同行验收样例：

```powershell
Get-Command fist          # C:\Users\victo\.local\bin\fist.cmd
fist version              # FIST-Mbt v0.3.6（moon.mod version 单一真源）
```

mcpconftest 安装器末尾的自检输出与之一致：

```
[ok] mcpconftest (PATH) → mcpconftest v0.9.0  <-- mcpconftest 命令已注册
```

即"一行命令安装和注册"验收标准：**shim 四件齐 + 用户级 PATH 已注册 + 命令可从 PATH 解析并输出版本**。

## 发布流程

1. 更新 `moon.mod` 的 `version`（并同步 `scripts/blackbox/install_onecmd.ps1` 的
   `$script:EmbeddedVersion` 与 `install.sh` 的 `EMBEDDED_VERSION`）。
2. 打包发行资产：

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\blackbox\release_zip.ps1
   # 或 Linux：
   bash scripts/blackbox/release_zip.sh
   ```

3. 将 `_release/mcpconftest-js-v<版本>.zip` 上传到 GitCode Release（tag `v<版本>`）。
4. 发布前自证（不发 Release 也能全流程验证）：`-LocalZip` / `MCP_LOCAL_ZIP` 跑安装器。

## 故障排查

| 现象 | 处理 |
|---|---|
| 下载全部失败 | Release 未发布 / 资产名不对 / 本机连不上外网。用 `-LocalZip` 离线装 |
| `mcpconftest` 找不到 | 新开终端（PATH 刷新）；或确认 `.local\bin` 在 PATH |
| shim 报了 bad interpreter | 重装；POSIX shim 必须是 LF 行尾 |
| node 版本过低 | 需要 ≥18（推荐 22+）；Windows 用 `winget install OpenJS.NodeJS.LTS` |
*（内容由AI生成，仅供参考）*
