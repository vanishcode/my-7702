# my-7702 · 最小化 EIP-7702 智能账户

一个最小、依赖极少、安全优先的 **EIP-7702** 委托合约。EOA 通过 type-4 授权把代码委托到本合约（不可升级单例，非 proxy），即可获得数项能力——**不使用任何 ERC-4337 概念**（无 relay / bundler / paymaster / EntryPoint / UserOp）。

A minimal, dependency-light, security-first **EIP-7702** delegate. An EOA delegates to this immutable singleton (no proxy) via a type-4 authorization and gains several capabilities — **with no ERC-4337** (no relay / bundler / paymaster / EntryPoint / UserOp).

## 功能 / Features

1. **批量执行 / Batch execution** — ERC-7821 `execute(bytes32 mode, bytes)`，兼容 MetaMask `wallet_sendCalls`(EIP-5792)。自发路径 `msg.sender == address(this)`，签名路径走 opData。
2. **Passkey (P256/WebAuthn)** — 完整链上 WebAuthn 断言验证（解析 `clientDataJSON`/`authenticatorData`、base64url challenge、UP/UV 标志、P256 预编译 `0x100`）。作为可装卸的 validator 插件。
3. **Session key** — 带作用域的临时密钥：时间窗 + 目标白名单 + 选择器白名单 + 单笔 ETH 上限。作为可装卸的 validator 插件。
4. **多签 / Multisig (M-of-N)** — 登记 N 个签名者 + 阈值 M：一笔执行需 ≥M 个不同登记签名者各对同一 `execHash` 签名（secp256k1 强制 low-s、严格升序去重）。作为可装卸的 validator 插件，只授权对外调用、碰不到 admin。
5. **插件系统 / Plugin system** — ERC-7579 子集，支持 **validator / executor / hook** 三类模块的自助安装/卸载。
