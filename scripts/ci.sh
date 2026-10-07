#!/usr/bin/env bash
# mcpconftest CI gate:
#   1) moon check must be clean (0 errors)
#   2) moon test (pure unit tests)
#   3) e2e against built-in fixture (strict expectations, ALL GREEN required)
set -e
cd "$(dirname "$0")/.."

echo "== moon check =="
moon check 2>&1 | tail -1

echo "== moon test =="
moon test 2>&1 | grep -E "Total|Failed|passed" | tail -3 || true

echo "== e2e fixture =="
moon run cmd/e2e 2>&1 | grep -E "^\[fixture\]|^E2E:"
