# 模块系统 / Module System

采用 ERC-7579 子集，支持三类模块的自助安装/卸载。

## 模块类型 / Module Types

| 类型 | 值 | 说明 |
|------|-----|------|
| Validator | 1 | 验证签名，替代或补充 ROOT ecrecover |
| Executor  | 2 | 外部调用入口，经 `executeFromExecutor` 回调 |
| Hook      | 4 | 执行前后包裹，可附加限制逻辑 |

## 已有模块 / Existing Modules

- **WebAuthnValidator** — passkey 验证（P256 / WebAuthn 断言）
- **SessionKeyValidator** — 带作用域的临时密钥（时间窗、目标白名单、ETH 上限）
- **MultisigValidator** — M-of-N 多签
- **ExampleExecutor** — executor 示例实现
- **SpendingLimitHook** — hook 示例实现（支出限制）

## 设计约束 / Constraints

- 模块一律 `CALL`，绝不 `DELEGATECALL`。
- `onUninstall` 包 `try/catch`，防止恶意模块阻止卸载。
- validator 与 executor 映射隔离，避免类型混淆。
