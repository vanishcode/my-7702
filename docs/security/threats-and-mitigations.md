# 威胁与缓解 / Threats & Mitigations

| 威胁 | 缓解措施 |
|------|---------|
| **越权** | admin 仅 ROOT 可达；非 ROOT 禁 self/zero call。 |
| **重放** | EIP-712 绑定 `chainId + address(this) + nonce`。 |
| **签名可塑性** | P256 与 secp256k1 均强制 low-s。 |
| **重入** | EIP-1153 瞬态锁 + CEI 模式。 |
| **重委托存储碰撞** | ERC-7201 命名空间 `my7702.account.v1`。 |
| **恶意模块** | 仅 CALL 不 DELEGATECALL；`onUninstall` try/catch；validator/executor 映射隔离。 |

## 已知风险 / Known Risk

MegaETH 官方文档**未显式确认** `0x100` P256 预编译；passkey 强依赖它，部署前请**上链探测**。若缺失：要么部署/指向外部 P256 verifier 回退（破坏零依赖），要么该网暂只用 secp256k1 + session。
