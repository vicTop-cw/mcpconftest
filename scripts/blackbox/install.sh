#!/usr/bin/env bash
# scripts/blackbox/install.sh —— curl 一条命令安装入口（Linux/WSL）
#
# 用户跑（首选，GitHub 镜像仓库 raw 直链；发布新版本时同步更新 URL）：
#   curl -fsSL https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/scripts/blackbox/install.sh | bash
# 备用（GitCode 镜像；该域匿名 raw 实测返回 HTTP 200 + HTML 页，只作备用）：
#   curl -fsSL https://gitcode.com/VictorTop/mcpconftest/-/raw/main/scripts/blackbox/install.sh | bash
#
# 下载源（自动 fallback）：
#   1. GitCode Release Assets 直链
#   2. AtomGit Release Assets 直链

set -euo pipefail

EMBEDDED_VERSION="0.7.0"

VERSION="${MCP_VERSION:-}"
FORCE=""
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE="1" ;;
    -*) : ;;                       # 忽略其它
    *)   VERSION="$arg" ;;         # 第一个非 flag 作 version
  esac
done

RAW_MOONMODS="https://raw.githubusercontent.com/vicTop-cw/mcpconftest/main/moon.mod https://gitcode.com/VictorTop/mcpconftest/-/raw/main/moon.mod https://atomgit.com/VictorTop/mcpconftest/raw/main/moon.mod"
if [ -n "${MCP_BASE_URL:-}" ]; then
  MCP_BASE_URL="${MCP_BASE_URL%/}"
  RAW_MOONMODS="${MCP_BASE_URL}/moon.mod"
  if [ -n "${MCP_LOCAL_ZIP:-}" ]; then
    echo "MCP_BASE_URL 与 MCP_LOCAL_ZIP 不能同时给（前者走镜像下载，后者跳过下载）" >&2; exit 1
  fi
fi
VERSION_SOURCE=""
if [ -z "$VERSION" ] && [ -n "${MCP_LOCAL_ZIP:-}" ]; then
  VERSION=$(basename "$MCP_LOCAL_ZIP" | sed -n 's/^mcpconftest-js-v\(.*\)\.zip$/\1/p')
  [ -n "$VERSION" ] && VERSION_SOURCE="本地 zip 文件名"
fi
if [ -z "$VERSION" ]; then
  for r in $RAW_MOONMODS; do
    mm=$(curl -fsSL --max-time 20 "$r" 2>/dev/null) || continue
    case "$mm" in
      "<"!DOCTYPE*|"<"doctype*|"<"html*)
        echo "  . $r 返回 HTML 页而不是文件（该源不可用作 raw 直链）" >&2; continue ;;
    esac
    VERSION=$(printf '%s' "$mm" | sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$VERSION" ]; then VERSION_SOURCE="$r"; break; fi
  done
fi
if [ -z "$VERSION" ]; then VERSION="$EMBEDDED_VERSION"; VERSION_SOURCE="内嵌默认值（外部源全部不可达）"; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}   mcpconftest Installer  v${VERSION}${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# --- 0. 预检 ---
need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd node; then
  echo -e "${RED}  [x] 需要 Node.js >=18${NC}"
  echo "   Ubuntu: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"
  echo "   或:     nvm install 22"
  exit 1
fi
NV=$(node -v)
NM=$(echo "$NV" | sed 's/^v//' | cut -d. -f1)
if [ "$NM" -lt 18 ]; then
  echo -e "${RED}  [x] Node.js $NV 过低，需要 >=18（推荐 22+，原生 WebSocket）${NC}"
  exit 1
fi
echo -e "${GREEN}  [ok] node $NV${NC}"

DL=""
if need_cmd curl; then DL="curl";
elif need_cmd wget; then DL="wget";
else echo -e "${RED}  [x] 需要 curl 或 wget${NC}"; exit 1; fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if need_cmd sudo; then SUDO="sudo";
  else echo -e "${RED}  [x] 需要 sudo 权限（或 root）${NC}"; exit 1; fi
fi

# --- 1. 构造下载 URL ---
ZIP="mcpconftest-js-v${VERSION}.zip"
URLS=(
  "https://gitcode.com/VictorTop/mcpconftest/releases/download/v${VERSION}/${ZIP}"
  "https://atomgit.com/VictorTop/mcpconftest/releases/download/v${VERSION}/${ZIP}"
)
if [ -n "${MCP_BASE_URL:-}" ]; then
  URLS=("${MCP_BASE_URL}/releases/download/v${VERSION}/${ZIP}")
fi

DEST="${HOME}/.local/share/mcpconftest"
BIN_DIR="${HOME}/.local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ""
echo -e "${YELLOW}  [download] ${ZIP} ...${NC}"
mkdir -p "$TMP"

ZIP_PATH="${TMP}/${ZIP}"
DOWNLOADED=0
if [ -n "${MCP_LOCAL_ZIP:-}" ]; then
  if [ ! -f "$MCP_LOCAL_ZIP" ]; then echo -e "${RED}  [x] MCP_LOCAL_ZIP 不存在: $MCP_LOCAL_ZIP${NC}"; exit 1; fi
  cp "$MCP_LOCAL_ZIP" "$ZIP_PATH"; DOWNLOADED=1
  echo -e "${GREEN}  [ok] 用本地 zip（跳过下载）: $MCP_LOCAL_ZIP${NC}"
fi
for URL in $( [ "$DOWNLOADED" -eq 1 ] || printf "%s\n" "${URLS[@]}" ); do
  echo -e "${DIM}  尝试: ${URL}${NC}"
  if [ "$DL" = "curl" ]; then
    HTTP_CODE=$(curl -sSL --max-time 60 -o "$ZIP_PATH" -w "%{http_code}" "$URL" 2>/dev/null) || HTTP_CODE="err"
  else
    HTTP_CODE=$(wget -q --timeout=60 -O "$ZIP_PATH" "$URL" 2>/dev/null && echo 200 || echo err)
  fi
  [ "$HTTP_CODE" != "200" ] && echo -e "${YELLOW}  HTTP ${HTTP_CODE} ... 换源${NC}"
  if [ -f "$ZIP_PATH" ] && [ "$(head -c 2 "$ZIP_PATH" 2>/dev/null)" != "PK" ]; then
    echo -e "${DIM}  . 该源给的不是 zip（首两字节 $(head -c 8 "$ZIP_PATH" 2>/dev/null | tr -d '\0')，多半是 HTML 页）${NC}"
    rm -f "$ZIP_PATH"; continue
  fi
  if [ -f "$ZIP_PATH" ] && [ "$(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH")" -gt 10240 ]; then
    KS=$(( $(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH") / 1024 ))
    echo -e "${GREEN}  [ok] 下载成功 (${KS} KB)${NC}"
    DOWNLOADED=1; break
  else
    rm -f "$ZIP_PATH"
  fi
done

if [ "$DOWNLOADED" -eq 0 ]; then
  echo -e "${RED}  [x] 下载全部失败 — Release 是否已发布？可离线安装：MCP_LOCAL_ZIP=/path/$ZIP bash install.sh${NC}"
  for U in "${URLS[@]}"; do echo -e "${DIM}      - ${U}${NC}"; done
  exit 1
fi

# --- 2. 解压 ---
echo ""
echo -e "${YELLOW}  [unzip] ...${NC}"
cd "$TMP"
unzip -o "$ZIP_PATH" -d extracted >/dev/null 2>&1 || { echo -e "${RED}  [x] 解压失败（需要 unzip）${NC}"; exit 1; }

JS_MAIN=$(find "$TMP/extracted" -maxdepth 2 -name "mcpconftest.js" | head -1)
if [ -z "$JS_MAIN" ]; then
  echo -e "${RED}  [x] zip 里没找到 mcpconftest.js${NC}"; exit 1
fi
echo -e "${GREEN}  [ok] mcpconftest.js${NC}"

# --- 3. 安装 ---
echo ""
echo -e "${YELLOW}  安装到 ${DEST} ...${NC}"
if [ -d "$DEST" ] && [ -z "$FORCE" ]; then
  echo -e "${YELLOW}  已存在，加 --force 覆盖${NC}"
fi
mkdir -p "$DEST"
cp "$JS_MAIN" "$DEST/mcpconftest.js"
echo '{"type":"module"}' > "$DEST/package.json"

# --- 4. shim + PATH ---
echo ""
echo -e "${YELLOW}  创建 shim + PATH ...${NC}"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/mcpconftest" <<SHIM
#!/usr/bin/env bash
# mcpconftest shim — v${VERSION}
exec node "${DEST}/mcpconftest.js" "\$@"
SHIM
chmod +x "$BIN_DIR/mcpconftest"

cat > "$BIN_DIR/mcpconftest-mbt" <<SHIM2
#!/usr/bin/env bash
# mcpconftest shim (alias) — v${VERSION}
exec node "${DEST}/mcpconftest.js" "\$@"
SHIM2
chmod +x "$BIN_DIR/mcpconftest-mbt"
# 硬门
for f in mcpconftest mcpconftest-mbt; do
  if [ ! -f "$BIN_DIR/$f" ] || [ ! -x "$BIN_DIR/$f" ]; then
    echo -e "${RED}  [x] shim 未全部写出/不可执行：$f${NC}"; exit 1
  fi
done

RC_FILE=""
case "${SHELL:-}" in
  */zsh) RC_FILE="${HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bashrc" ;;
  *)     RC_FILE="${HOME}/.profile" ;;
esac
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
if [ -f "$RC_FILE" ]; then
  if ! grep -qF '.local/bin' "$RC_FILE" 2>/dev/null; then
    echo "" >> "$RC_FILE"
    echo "# mcpconftest installer" >> "$RC_FILE"
    echo "$PATH_LINE" >> "$RC_FILE"
    echo -e "${GREEN}  [ok] 追加 .local/bin 到 ${RC_FILE}${NC}"
  else
    echo -e "${DIM}  .local/bin 已在 ${RC_FILE}${NC}"
  fi
else
  echo "$PATH_LINE" > "$RC_FILE"
  echo -e "${GREEN}  [ok] 创建 ${RC_FILE}${NC}"
fi
export PATH="${BIN_DIR}:$PATH"

# --- 5. 自检 ---
echo ""
echo -e "${YELLOW}  自检...${NC}"
V=$(node "${DEST}/mcpconftest.js" version 2>&1 | head -1)
echo -e "  ${GREEN}[ok] ${V}${NC}"

V2=$("$BIN_DIR/mcpconftest" version 2>&1 | head -1)
echo -e "  ${GREEN}[ok] mcpconftest (PATH) → ${V2}  <-- mcpconftest 命令已注册${NC}"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   [ok] mcpconftest v${VERSION} 安装完成！${NC}"
echo -e "${GREEN}   新开终端后运行:  mcpconftest list-checks${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${DIM}  已将 ${BIN_DIR} 追加到 ${RC_FILE} — 新开终端生效${NC}"
