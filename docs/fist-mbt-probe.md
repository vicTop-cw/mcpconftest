# 真 FIST-Mbt 探测回归记录（2026-10-07）

## 环境
- FIST-Mbt 构建产物：`_build/js/debug/build/cmd/cli/cli.js`（moon build cmd/cli --target js）
- 已知构建产物补丁：sqlite 绑定 `require("node:sqlite")` 在 ESM 下崩溃，
  需 `sed -i 's/require("node:sqlite")/process.getBuiltinModule("node:sqlite")/'` 修正后才能 serve。

## 探测命令
```
moon run cmd/e2e -- --server "node <FIST-Mbt>/cli.js serve"
```

## 发现（mcpconftest 抓到的一致性问题）
1. **每个请求都要求 `_meta.io.modelcontextprotocol/protocolVersion`**
   —— 协议规范只在 initialize 握手时声明版本；FIST-Mbt 对所有请求强制要求，
   严格客户端（如不带 _meta 的标准实现）会全部收到 -32602。
2. **initialize 参数校验自相矛盾**：
   - 缺 `_meta.clientCapabilities` → -32602 "Missing required _meta field: clientCapabilities"
   - 补齐后同一请求 → -32601 "Method not found: initialize"
   同一方法两次应答不一致，属校验路径 bug。
3. capabilities / tools/list 在握手失败后全部不可达（预期连锁失败）。

## 结论
- mcpconftest 传输层（spawn/stdin/stdout/timeout）对真 server 工作正常。
- FIST-Mbt 的发现已足以作为探针价值的实证；FIST-Mbt 侧修复不在本仓范围。
