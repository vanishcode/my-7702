# 不可破坏的安全不变式 / Invariants

以下不变式不可破坏。任何改动必须通过对抗性测试验证（见 `test/Security.t.sol`）。

## 1. Admin 仅 ROOT 可达

- `install` / `uninstall` / 模块配置 等 admin 操作必须满足：
  - `msg.sender == address(this)`（自发路径），或
  - root ecrecover 验证通过。

## 2. 非 ROOT 路径禁 self-call

- session / executor 等外部路径，**逐笔强制** `to != address(this) && to != address(0)`。
- 防止非授权路径触碰 admin 接口或烧币。

## 3. 模块隔离

- 模块一律 `CALL`，绝不 `DELEGATECALL`。
- `onUninstall` 包 `try/catch`。
- validator 映射与 executor 映射严格隔离。

## 4. 签名防重放与防可塑性

- 每个签名 digest 经 EIP-712 绑定 `chainId + address(this) + nonce`。
- P256 与 secp256k1 均强制 low-s。

## 5. 存储命名空间

- 持久状态必须放在 ERC-7201 命名空间 `my7702.account.v1`。
- 禁止直接使用裸槽位，防止重委托时存储碰撞。
