# Account.sol 核心 / Account Core

`src/Account.sol` 是核心委托单例，承担以下职责：

- **ERC-7821 `execute`** — 批量执行入口；自发路径 `msg.sender == address(this)`，签名路径解析 `opData`。
- **模块注册表** — `installModule` / `uninstallModule` / `isModuleInstalled`，仅 ROOT 可达。
- **ERC-1271** — `isValidSignature` 支持 ROOT ecrecover 或路由到已安装 validator。
- **Nonce** — 顺序递增，防重放。
- **EIP-1153 重入锁** — 瞬态存储实现低开销重入保护。
- **ERC-7201 存储** — 全部持久状态放在命名空间 `my7702.account.v1`，防止重委托存储碰撞。
