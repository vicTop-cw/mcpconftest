#!/usr/bin/env bash
# Demo: probe the fully-compliant MCP server
set -e
cd "$(dirname "$0")/../.."

echo "=== Demo: mcpconftest vs fully-compliant MCP server ==="
echo ""

# Clean previous report
rm -rf mcpconftest-demo-report

# Run probe against compliant server
moon run cmd -- run --server "node tests/demo/compliant_server.js" --report ./mcpconftest-demo-report

echo ""
echo "=== Report (mcpconftest-demo-report/report.md) ==="
cat mcpconftest-demo-report/report.md

echo ""
echo "=== JSON summary ==="
node -e "
const r = require('./mcpconftest-demo-report/report.json');
console.log('Server:', r.server_cmd);
console.log('Protocol:', r.protocol_version);
console.log('Pass:', r.summary.pass);
console.log('Fail:', r.summary.fail);
console.log('Skip:', r.summary.skip);
console.log('Total timing:', r.total_timing_ms + 'ms');
console.log('Avg per check:', r.avg_timing_ms + 'ms');
"
