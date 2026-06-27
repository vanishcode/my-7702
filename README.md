# my-7702 · 最小化 EIP-7702 智能账户 / minimal EIP-7702 smart account

一个最小、依赖极少、安全优先的 **EIP-7702** 委托合约。EOA 通过 type-4 授权把代码委托到本合约（不可升级单例，非 proxy），即可获得数项能力——**不使用任何 ERC-4337 概念**（无 relay / bundler / paymaster / EntryPoint / UserOp）。

A minimal, dependency-light, security-first **EIP-7702** delegate. An EOA delegates to this immutable singleton (no proxy) via a type-4 authorization and gains several capabilities — **with no ERC-4337** (no relay / bundler / paymaster / EntryPoint / UserOp).

## 功能速览 / Features at a Glance

1. **批量执行 / Batch execution** — ERC-7821 `execute`，兼容 MetaMask `wallet_sendCalls`(EIP-5792)。
2. **Passkey (P256/WebAuthn)** — 完整链上 WebAuthn 断言验证，可装卸 validator 插件。
3. **Session key** — 带作用域的临时密钥（时间窗 + 目标白名单 + ETH 上限）。
4. **多签 / Multisig (M-of-N)** — 登记签名者 + 阈值，仅授权对外调用。
5. **插件系统 / Plugin system** — ERC-7579 子集，支持 validator / executor / hook 自助安装/卸载。

## 快速开始 / Quickstart

```bash
forge build --sizes
forge test -vvv
forge fmt
```

详细构建、部署与安全说明见 [`docs/`](docs/)。

## 文档索引 / Docs

| 分类 | 文档 |
|------|------|
| 简介与功能 | [`docs/intro.md`](docs/intro.md) |
| 快速开始 | [`docs/quickstart.md`](docs/quickstart.md) |
| 架构设计 | [`docs/architecture/`](docs/architecture/) — 总览、Account 核心、模块系统 |
| 安全 | [`docs/security/`](docs/security/) — 不变式、威胁与缓解 |
| 部署指南 | [`docs/deployment/megaeth-testnet.md`](docs/deployment/megaeth-testnet.md) |
| 开发规范 | [`docs/development/`](docs/development/) — 代码风格、测试指南 |
