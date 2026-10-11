#!/usr/bin/env pwsh
<#
scripts/blackbox/install_onecmd.ps1 —— irm 一条命令安装入口（mcpconftest, v2 Release Assets 版）

用户跑（首选，GitHub 镜像仓库 raw 直链；发布新版本时同步更新 URL）：
  iex ((irm https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))
# BUG-113 同款：本文件含中文，必须带 UTF-8 BOM；`irm` 会把 BOM 留成首字符 U+FEFF，
# `iex` 就不再把 `param()` 当首语句 ⇒ 先 TrimStart 再去 iex。`powershell -File` 走磁盘没这问题。
备用（GitCode 镜像，同一份内容）：
  irm https://gitcode.com/VictorTop/mcpconftest/-/raw/main/scripts/blackbox/install_onecmd.ps1 | iex
# 注意：GitCode 匿名 raw 直链实测返回 HTTP 200 + 一整页 HTML（不是文件正文），
# 该备用入口可能无法直接 iex；脚本本体仍可从仓库 clone 后本地执行。

下载源（自动按序 fallback）：
  1. GitCode Release Assets 直链（https://gitcode.com/VictorTop/mcpconftest/releases/download/vX/...）
  2. AtomGit Release Assets 直链（https://atomgit.com/VictorTop/mcpconftest/releases/download/vX/...）
版本解析源（自动按序探测，探测不到退回内嵌默认值）：
  raw.githubusercontent.com / gitcode.com / atomgit.com 的 moon.mod（HTML sniff 防护）
#>

param(
  # 版本号唯一真源 = moon.mod（发布资产名也从它生成）。不传时按序解析；
  # 所有外部源都不可达时退回内嵌默认值（发布新版本需同步更新 $script:EmbeddedVersion）。
  [string]$Version = "",
  [switch]$Force,
  # 离线/内网/发布前自证：给了本地 zip 就跳过下载（不发 Release 也能装）
  [string]$LocalZip = "",
  # 镜像入口：给一个 base（内网镜像 / 本机 http.server）就只从它下面按**与公网同形的路径**取
  # moon.mod 与资产 —— 这样"下载这一步"在没有公网 Release 时也能被真跑一遍，而不是只能靠 -LocalZip 绕行。
  [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"
$script:EmbeddedVersion = "0.7.0"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   mcpconftest Installer  v$Version" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

function Test-Cmd($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd "node")) { Write-Host "  [x] 需要 Node.js >=18 (winget install OpenJS.NodeJS.LTS)" -ForegroundColor Red; exit 1 }
$nv = (node -v)
$nm = [int]($nv -replace '^v', '' -split '\.')[0]
if ($nm -lt 18) { Write-Host "  [x] Node.js $nv 过低，需要 >=18（推荐 22+，原生 WebSocket）" -ForegroundColor Red; exit 1 }
Write-Host "  [ok] node $nv" -ForegroundColor Green

# BUG-116 同款：本机走系统代理时 .NET 栈会瞬时抛「基础连接已经关闭」，同一时刻 curl.exe 能得 200。
# moon.mod 与资产两发都：.NET 抛错且无 HTTP 响应（传输层）时，换 curl.exe 再取一次。
$script:CurlExe = if (Get-Command curl.exe -ErrorAction SilentlyContinue) { (Get-Command curl.exe).Source } else { "" }
function Get-UrlTo([string]$Url, [string]$OutFile, [int]$Sec) {
  if ($script:CurlExe -eq "") { return $false }
  try {
    & $script:CurlExe -fsSL --retry 3 --retry-delay 2 --retry-all-errors --max-time $Sec -o $OutFile $Url 2>$null | Out-Null
    return (($LASTEXITCODE -eq 0) -and (Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0))
  } catch {
    return $false
  }
}

# ---- 版本解析 ----
$rawUrls = @(
  "https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/moon.mod",
  "https://gitcode.com/VictorTop/mcpconftest/-/raw/main/moon.mod",
  "https://atomgit.com/VictorTop/mcpconftest/raw/main/moon.mod"
)
if ($BaseUrl -ne "") { $rawUrls = @(($BaseUrl.TrimEnd('/') + "/moon.mod")) }
$versionSource = "命令行参数"
if ($Version -eq "") {
  if ($LocalZip -ne "" -and (Split-Path -Leaf $LocalZip) -match '^mcpconftest-js-v(.+)\.zip$') {
    $Version = $matches[1]; $versionSource = "本地 zip 文件名"
  } else {
    foreach ($r in $rawUrls) {
      try {
        $mm = (Invoke-WebRequest -Uri $r -UseBasicParsing -TimeoutSec 20).Content
        if ($mm -isnot [string]) { $mm = [Text.Encoding]::UTF8.GetString($mm) }
        if ($mm -match '^\s*<(!DOCTYPE|html)') {
          Write-Host "  . $r 返回 HTML 页而不是文件（该源不可用作 raw 直链）" -ForegroundColor DarkGray
          continue
        }
        if ($mm -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $Version = $matches[1]; $versionSource = $r; break }
        Write-Host "  . $r 的正文里没有可解析的 version 行" -ForegroundColor DarkGray
      } catch {
        $why = ($_.Exception.Message -replace '\s+', ' ')
        if (-not $_.Exception.Response) {
          $tmp = [IO.Path]::GetTempFileName()
          if (Get-UrlTo $r $tmp 20) { $mm = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) }
          Remove-Item $tmp -Force -ErrorAction SilentlyContinue
          if ($mm) {
            if ($mm -match '^\s*<(!DOCTYPE|html)') { Write-Host "  . $r （curl 臂）返回 HTML 页而不是文件" -ForegroundColor DarkGray; continue }
            if ($mm -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $Version = $matches[1]; $versionSource = ($r + " [curl-fallback]"); break }
          } else {
            Write-Host "  . 取不到 $r ：$why（curl 臂也不可用）" -ForegroundColor DarkGray
          }
        } else {
          Write-Host "  . 取不到 $r ：$why" -ForegroundColor DarkGray
        }
      }
    }
  }
}
if ($Version -eq "") { $Version = $script:EmbeddedVersion; $versionSource = "内嵌默认值（外部源全部不可达）" }
Write-Host "  目标版本 v$Version（来源：$versionSource）" -ForegroundColor DarkGray

# ---- 下载 ----
$zipName = "mcpconftest-js-v$Version.zip"
$urls = @(
  "https://gitcode.com/VictorTop/mcpconftest/releases/download/v$Version/$zipName",
  "https://atomgit.com/VictorTop/mcpconftest/releases/download/v$Version/$zipName"
)
if ($BaseUrl -ne "") { $urls = @(($BaseUrl.TrimEnd('/') + "/releases/download/v$Version/$zipName")) }
if ($BaseUrl -ne "" -and $LocalZip -ne "") {
  Write-Host "  [x] -BaseUrl 与 -LocalZip 不能同时给（前者走镜像下载，后者跳过下载）" -ForegroundColor Red
  exit 1
}

$dest = Join-Path $env:LOCALAPPDATA "mcpconftest"
$bin  = Join-Path $env:USERPROFILE ".local\bin"
$temp = Join-Path $env:TEMP ("mcpconftest-install-" + [guid]::NewGuid().ToString("N"))

Write-Host ""
Write-Host "  [download] $zipName ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $temp -Force | Out-Null

$zipPath = Join-Path $temp $zipName
$downloaded = $false
if ($LocalZip -ne "") {
  if (-not (Test-Path $LocalZip)) {
    Write-Host "  [x] -LocalZip 指向的文件不存在: $LocalZip" -ForegroundColor Red
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
  }
  $li = Get-Item $LocalZip
  Copy-Item $li.FullName $zipPath -Force
  Write-Host ("  [ok] 用本地 zip（跳过下载）: " + $li.FullName + " (" + [math]::Round($li.Length/1KB,1) + " KB)") -ForegroundColor Green
  $downloaded = $true
}
foreach ($u in $(if ($downloaded) { @() } else { $urls })) {
  Write-Host "  尝试: $u" -ForegroundColor DarkGray
  for ($try = 1; $try -le 3; $try++) {
    $retry = $false
    try {
      Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
      $magic = [IO.File]::ReadAllBytes($zipPath)[0..1]
      if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        Write-Host "  . 该源给的不是 zip（前两字节 $([BitConverter]::ToString($magic))，多半是 HTML 页）" -ForegroundColor DarkGray
        Remove-Item $zipPath -Force
        break
      }
      if ((Get-Item $zipPath).Length -gt 10KB) {
        Write-Host "  [ok] 下载成功 ($([math]::Round((Get-Item $zipPath).Length/1KB,1)) KB)" -ForegroundColor Green
        $downloaded = $true
      } else { Remove-Item $zipPath -Force }
      break
    } catch {
      $resp = $_.Exception.Response
      $code = if ($resp) { [int]$resp.StatusCode } else { "n/a(传输层)" }
      $why = ($_.Exception.Message -replace '\s+', ' ')
      Write-Host ("  第 $try 次失败 HTTP " + $code + " (" + $_.Exception.GetType().Name + ") " + $why + " ...") -ForegroundColor Yellow
      if ($resp) { break }
      $tmpOk = Get-UrlTo $u ($zipPath + ".curltry") 60
      if ($tmpOk) {
        $m2 = [IO.File]::ReadAllBytes($zipPath + ".curltry")[0..1]
        if ($m2[0] -eq 0x50 -and $m2[1] -eq 0x4B -and ((Get-Item ($zipPath + ".curltry")).Length -gt 10KB)) {
          Move-Item ($zipPath + ".curltry") $zipPath -Force
          Write-Host "  [ok] curl-fallback 下载成功 ($([math]::Round((Get-Item $zipPath).Length/1KB,1)) KB)" -ForegroundColor Green
          $downloaded = $true
        } else { Remove-Item ($zipPath + ".curltry") -Force }
      }
      if ($downloaded) { break }
      if ($try -lt 3) { $retry = $true }
    }
    if ($retry) { Start-Sleep -Seconds (2 * $try) } else { break }
  }
  if ($downloaded) { break }
}
if (-not $downloaded) {
  Write-Host "  [x] 下载全部失败（每个源的状态见上）。三种可能：Release 未发布 / 资产名不是 $zipName / 本机连不上外网" -ForegroundColor Red
  foreach ($u in $urls) { Write-Host "      - $u" -ForegroundColor DarkGray }
  Write-Host "  离线安装：& <脚本路径> -Version $Version -LocalZip $env:USERPROFILE\Downloads\$zipName" -ForegroundColor DarkGray
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue; exit 1
}

# ---- 解压 ----
Write-Host ""
Write-Host "  [unzip] ..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $temp -Force
$jsMain = Get-ChildItem -Path $temp -Filter "mcpconftest.js" -Recurse -File | Select-Object -First 1
if (-not $jsMain) { Write-Host "  [x] zip 里没找到 mcpconftest.js" -ForegroundColor Red; Remove-Item -Recurse -Force $temp; exit 1 }
Write-Host "  [ok] mcpconftest.js ($([math]::Round($jsMain.Length/1024,1)) KB)" -ForegroundColor Green

# ---- 安装 ----
Write-Host ""
Write-Host "  安装到 $dest ..." -ForegroundColor Yellow
if (Test-Path $dest) { if ($Force) { Remove-Item -Recurse -Force $dest } else { Write-Host "  已存在，加 -Force 覆盖" -ForegroundColor Yellow } }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item $jsMain.FullName "$dest\mcpconftest.js" -Force
# 产物为 ESM bundle（node:child_process 动态 import），ESM 目录下全链路可用，无需 patch 脚本。
'{"type":"module"}' | Set-Content "$dest\package.json" -Encoding ASCII

# ---- shim + PATH ----
Write-Host ""
Write-Host "  创建 shim + PATH ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $bin -Force | Out-Null
# 注释一律纯 ASCII：这下面用 -Encoding ASCII 写盘，非 ASCII 字符会被替换成 '?'
$shimCmd = "@echo off`r`nREM mcpconftest shim (v" + $Version + ")`r`nnode `"$dest\mcpconftest.js`" %*`r`n"
Set-Content -Path "$bin\mcpconftest.cmd"      -Value $shimCmd -Encoding ASCII
Set-Content -Path "$bin\mcpconftest-mbt.cmd"  -Value $shimCmd -Encoding ASCII
# BUG-105 同款：POSIX shell 不按 PATHEXT 解析命令名 ⇒ 再写无扩展名 shim；换行必须 LF。
$shimSh = '#!/bin/sh' + "`n" + 'exec node "' + $dest + '\mcpconftest.js" "$@"' + "`n"
Set-Content -Path "$bin\mcpconftest"     -Value $shimSh -Encoding ASCII -NoNewline
Set-Content -Path "$bin\mcpconftest-mbt" -Value $shimSh -Encoding ASCII -NoNewline
# 硬门：四件齐才算装上。少一件就是"文档说装好了、命令却找不到"的那类坑，绝不静默放过。
$shimMissing = @()
foreach ($f in @("mcpconftest.cmd", "mcpconftest-mbt.cmd", "mcpconftest", "mcpconftest-mbt")) {
  if (-not (Test-Path (Join-Path $bin $f))) { $shimMissing += $f }
}
if ($shimMissing.Count -gt 0) {
  Write-Host "  [x] shim 未全部写出：$($shimMissing -join ', ')（期望 .cmd + 无扩展名 POSIX 两份）" -ForegroundColor Red
  exit 1
}

$pathUser = [Environment]::GetEnvironmentVariable("PATH", "User")
$pathChanged = $false
if ($pathUser -notlike "*$bin*") {
  [Environment]::SetEnvironmentVariable("PATH", "$bin;$pathUser", "User")
  $env:PATH = "$bin;$env:PATH"; $pathChanged = $true
}

Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue

# ---- 自检 ----
Write-Host ""
Write-Host "  自检..." -ForegroundColor Yellow
function Invoke-McpNative {
  param($Exe, [string[]]$ExeArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { $out = (& $Exe @ExeArgs 2>$null | Out-String) } finally { $ErrorActionPreference = $prevEap }
  return $out.Trim()
}
$jsVer = Invoke-McpNative -Exe "node" -ExeArgs @("$dest\mcpconftest.js", "version")
if ($jsVer) {
  Write-Host "  [ok] $jsVer" -ForegroundColor Green
  Write-Host "  [ok] mcpconftest.js 可执行" -ForegroundColor Green
} else {
  Write-Host "  [x] 产物跑不出版本（node 不在 PATH 或产物损坏）：node `"$dest\mcpconftest.js`" version 无 stdout 回执" -ForegroundColor Red
  exit 1
}
$shimCmd = Get-Command mcpconftest -ErrorAction SilentlyContinue
if ($shimCmd) {
  $vv = Invoke-McpNative -Exe $shimCmd.Source -ExeArgs @("version")
  if ($vv) { Write-Host "  [ok] mcpconftest (PATH) → $vv  <-- mcpconftest 命令已注册" -ForegroundColor Green }
  else {
    Write-Host "  [x] mcpconftest 解析到 $($shimCmd.Source)，但跑起来没有回执" -ForegroundColor Red
    exit 1
  }
} else {
  Write-Host "  当前会话 PATH 未刷新（新开终端即可）" -ForegroundColor Yellow
}
$shBytes = [IO.File]::ReadAllBytes((Join-Path $bin "mcpconftest"))
$shHead = [Text.Encoding]::ASCII.GetString($shBytes[0..8])
if ($shHead -eq "#!/bin/sh" -and ($shBytes -notcontains 13)) {
  Write-Host "  [ok] mcpconftest (POSIX shim, LF) 供 Git Bash / MSYS 使用" -ForegroundColor Green
} else {
  Write-Host "  [x] POSIX shim 头不对或含 CR（bash 下会报 bad interpreter）" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "   [ok] mcpconftest v$Version 安装完成！" -ForegroundColor Green
Write-Host "   新开终端:  mcpconftest list-checks" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
if ($pathChanged) { Write-Host "  已将 $bin 追加到用户级 PATH" -ForegroundColor DarkGray }
