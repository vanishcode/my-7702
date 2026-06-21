# my-7702 · 最小化 EIP-7702 智能账户 / minimal EIP-7702 smart account

一个最小、依赖极少、安全优先的 **EIP-7702** 委托合约。EOA 通过 type-4 授权把代码委托到本合约（不可升级单例，非 proxy），即可获得四项能力——**不使用任何 ERC-4337 概念**（无 relay / bundler / paymaster / EntryPoint / UserOp）。

A minimal, dependency-light, security-first **EIP-7702** delegate. An EOA delegates to this immutable singleton (no proxy) via a type-4 authorization and gains four capabilities — **with no ERC-4337** (no relay / bundler / paymaster / EntryPoint / UserOp).

> 设计与决策详见 [PLAN.md](PLAN.md)。/ See [PLAN.md](PLAN.md) for the full design and decisions.

## 功能 / Features

1. **批量执行 / Batch execution** — ERC-7821 `execute(bytes32 mode, bytes)`，兼容 MetaMask `wallet_sendCalls`(EIP-5792)。自发路径 `msg.sender == address(this)`，签名路径走 opData。
2. **Passkey (P256/WebAuthn)** — 完整链上 WebAuthn 断言验证（解析 `clientDataJSON`/`authenticatorData`、base64url challenge、UP/UV 标志、P256 预编译 `0x100`）。作为可装卸的 validator 插件。
3. **Session key** — 带作用域的临时密钥：时间窗 + 目标白名单 + 选择器白名单 + 单笔 ETH 上限。作为可装卸的 validator 插件。
4. **插件系统 / Plugin system** — ERC-7579 子集，支持 **validator / executor / hook** 三类模块的自助安装/卸载。

## 架构 / Architecture

```sh
EOA --(7702 type-4 委托)--> Account.sol (delegate singleton, address(this)==EOA)
  ├─ execute(mode, data)            ERC-7821 批量；id1 自发 / id2 opData 签名
  ├─ executeFromExecutor(...)       仅已安装 executor 回调，禁 self-call
  ├─ isValidSignature(...)          ERC-1271：ROOT ecrecover 或路由到 validator
  ├─ install/uninstall/isInstalled  模块注册表（onlySelf）
  └─ 内置 ROOT validator = ecrecover==address(this)
       ├─ WebAuthnValidator (type1)   passkey
       ├─ SessionKeyValidator (type1) session
       ├─ ExampleExecutor (type2)     示例
       └─ SpendingLimitHook (type4)   示例
```

**鉴权优先级 / auth precedence**：ROOT（`msg.sender==self` 或 root ecrecover）> validator 模块 > executor 模块；hook 仅前后包裹。
**核心不变式 / core invariant**：只有 ROOT 路径可 self-call（触达 admin）；session / executor 路径逐笔强制 `to != address(this) && to != address(0)`。

## 文件 / Layout

```sh
src/
  Account.sol                  核心委托单例 / core delegate singleton
  interfaces/                  IERC7579Modules, IERC1271
  lib/                         AccountStorage(ERC-7201), ECDSA, P256, Base64Url, WebAuthn, Types
  modules/                     WebAuthnValidator, SessionKeyValidator, SpendingLimitHook, ExampleExecutor
script/                        Deploy.s.sol, Delegate.s.sol
test/                         40 个测试 + test/vendor/P256Verifier.sol（仅测试用）
```

## 构建与测试 / Build & test

```bash
forge build --sizes
forge test -vvv
forge fmt --check
```

> 测试为何在 `0x100` etch 一个 P256 verifier：本地 prague EVM 不带该预编译。生产 `src/` **零第三方依赖**，仅在测试里 etch [Daimo 的自包含 verifier](https://github.com/daimo-eth/p256-verifier)（`test/vendor/`）。
> Why tests etch a P256 verifier at `0x100`: the local prague EVM lacks that precompile. Production `src/` has **zero third-party deps**; tests etch Daimo's self-contained verifier (`test/vendor/`).

## 部署到 MegaETH 测试网 / Deploy to MegaETH testnet

链信息 / chain: id **6343**, RPC `https://carrot.megaeth.com/rpc`, 浏览器 Etherscan `https://testnet-mega.etherscan.io`, 水龙头 `https://testnet.megaeth.com`。`.env` 需 `PRIVATE_KEY`（验证合约还需 `ETHERSCAN_API_KEY`）。

```bash
# 0) 确认链 id（避开已废弃的 6342）/ confirm chain id (avoid deprecated 6342)
cast chain-id --rpc-url megaeth_testnet            # 期望 6343

# 1) ⚠️ 先探测 P256 预编译 0x100（passkey 依赖它）/ probe the P256 precompile first (passkey depends on it)
#    用已知合法 160 字节向量；返回 0x..01 表示存在 / known-good vector; 0x..01 means present
cast call 0x0000000000000000000000000000000000000100 \
  0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4da73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d604aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff37618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e \
  --rpc-url megaeth_testnet

# 2) 部署实现与模块 / deploy implementation + modules
forge script script/Deploy.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast

# 3) 委托 EOA 并自调用批量（cast 自动为该 EOA 签授权）/ delegate the EOA + self-batch
cast send --rpc-url megaeth_testnet --private-key $PRIVATE_KEY \
  --auth <ACCOUNT_IMPL> $EOA <execute calldata> --gas-limit 3000000

# 3') 或用脚本委托并安装一个 validator 插件 / or delegate + install a validator via script
IMPL=<ACCOUNT_IMPL> VALIDATOR=<SESSION_OR_WEBAUTHN_VALIDATOR> \
  forge script script/Delegate.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast

# 4) 验证 / verify (Etherscan v2，需 ETHERSCAN_API_KEY)
forge verify-contract --chain 6343 --verifier etherscan \
  --verifier-url 'https://api.etherscan.io/v2/api' --etherscan-api-key $ETHERSCAN_API_KEY \
  <addr> src/Account.sol:Account
```

> MegaETH 采用双 gas 模型（普通转账≈60k），7702 交易请给足 `--gas-limit`。
> MegaETH uses a dual gas model (~60k for a transfer); set a generous `--gas-limit` on 7702 txs.

## 安全 / Security

威胁与缓解详见 [PLAN.md §7](PLAN.md)。要点：越权（admin 仅 ROOT 可达、非 ROOT 禁 self/zero）、重放（EIP-712 绑定 chainId+account+nonce）、可塑性（P256 与 secp256k1 强制 low-s）、重入（EIP-1153 瞬态锁 + CEI）、重委托存储碰撞（ERC-7201 命名空间）、恶意模块（仅 CALL 不 DELEGATECALL、`onUninstall` try/catch、validator/executor 映射隔离）。

## ⚠️ 已知风险 / known risk

MegaETH 官方文档**未显式确认** `0x100` P256 预编译；passkey 强依赖它，部署前请按上面第 1 步**上链探测**。若缺失：要么部署/指向一个外部 P256 verifier 回退（破坏零依赖），要么该网暂只用 secp256k1 + session。详见 [PLAN.md §12](PLAN.md)。

## 待定实现选项 / open implementation choices

见 [PLAN.md §13](PLAN.md)：WebAuthn 手写 vs vendor 审计文件（当前手写）、nonce 模型（当前顺序）、session 允许列表表示（当前内联数组）、累计预算（当前不做）。
