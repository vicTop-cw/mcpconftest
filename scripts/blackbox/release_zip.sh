#!/usr/bin/env bash
# scripts/blackbox/release_zip.sh —— 打包 mcpconftest JS 发行资产（Linux/WSL）
# 内容：mcpconftest.js（moon build --target js --release 的可执行 bundle）+ package.json
# 用法：bash scripts/blackbox/release_zip.sh   （MCP_VERSION=0.7.0 可覆盖版本）
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${MCP_VERSION:-}"
if [ -z "$VERSION" ]; then
  VERSION=$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/moon.mod" | head -1)
fi
if [ -z "$VERSION" ]; then echo "无法从 moon.mod 解析版本，请用 MCP_VERSION" >&2; exit 1; fi
echo "=== mcpconftest release zip v$VERSION ==="

echo "[build] moon build --target js --release ..."
moon build --target js --release

JS_MAIN=""
for c in "$REPO_ROOT/_build/js/release/build/cmd/cmd.js" "$REPO_ROOT/_build/js/debug/build/cmd/cmd.js"; do
  [ -f "$c" ] && JS_MAIN="$c" && break
done
if [ -z "$JS_MAIN" ]; then echo "[x] cmd.js 产物未找到" >&2; exit 1; fi
echo "[ok] $JS_MAIN"

STAGE="$REPO_ROOT/_release_stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$JS_MAIN" "$STAGE/mcpconftest.js"
printf '%s\n' '{"type":"module"}' > "$STAGE/package.json"

OUT="$REPO_ROOT/_release"
mkdir -p "$OUT"
ZIP="$OUT/mcpconftest-js-v$VERSION.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
  (cd "$STAGE" && zip -q "$ZIP" mcpconftest.js package.json)
else
  python3 - "$ZIP" "$STAGE" <<'PY'
import sys, zipfile, os
z, s = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as f:
    for n in ("mcpconftest.js", "package.json"):
        f.write(os.path.join(s, n), n)
PY
fi
rm -rf "$STAGE"

echo "[check] node mcpconftest.js version ..."
TMPC=$(mktemp -d); trap 'rm -rf "$TMPC"' EXIT
unzip -oq "$ZIP" -d "$TMPC"
VO=$(node "$TMPC/mcpconftest.js" version 2>&1 | head -1)
[ -n "$VO" ] || { echo "[x] 产物跑不出版本" >&2; exit 1; }
echo "  [ok] $VO"
echo ""
echo "[ok] $ZIP ($(( $(stat -c%s "$ZIP" 2>/dev/null || stat -f%z "$ZIP") / 1024 )) KB)"
