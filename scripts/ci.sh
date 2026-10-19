#!/usr/bin/env bash
# mcpconftest CI gate:
#   1) moon check must be clean (0 errors) on js + native
#   2) moon test (pure unit tests) on js + native
#   3) e2e against built-in fixture (strict expectations, ALL GREEN required)
set -e
cd "$(dirname "$0")/.."

for target in js native; do
  echo "== moon check ($target) =="
  moon check --target "$target" 2>&1 | tail -1

  echo "== moon test ($target) =="
  moon test --target "$target" 2>&1 | grep -E "Total|Failed|passed" | tail -3 || true
done

echo "== e2e fixture =="
moon run cmd/e2e 2>&1 | grep -E "^\[fixture\]|^E2E:"

echo "== fixture snapshot diff (R5) =="
TMP_R="$(mktemp -d)"
moon run cmd -- run --fixture --report "$TMP_R" 2>/dev/null || true
pwsh -File scripts/verify-fixture.ps1 -ReportJson "$TMP_R/report.json" -ExpectedJson scripts/fixture-expected.json
rm -rf "$TMP_R"
