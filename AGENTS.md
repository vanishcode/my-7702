# AGENTS.md

最小化 EIP-7702 智能账户（Foundry / Solidity 0.8.28 / evm_version=prague / via_ir）。
Minimal EIP-7702 smart account. No ERC-4337. Target chain: MegaETH testnet (6343).

## 命令 / Commands

- 构建 / build: `forge build --sizes`
- 测试 / test: `forge test -vvv`
- 格式（CI 会 `--check`）/ format: `forge fmt`

## 架构 / Architecture

- `src/Account.sol` — 核心委托单例：ERC-7821 `execute`、模块注册表、ERC-1271、nonce、EIP-1153 重入锁、ERC-7201 存储。
- `src/modules/*` — validator(1)/executor(2)/hook(4) 模块：WebAuthn(passkey)、SessionKey、SpendingLimitHook、ExampleExecutor。
- `src/lib/*` — P256(0x100 预编译)、WebAuthn、Base64Url、ECDSA(low-s)、AccountStorage(ERC-7201)、Types(Call)。

## 不可破坏的安全不变式 / Invariants (do not break)

- admin（install/uninstall、模块配置）仅 ROOT 可达：`require(msg.sender == address(this))` 或 root ecrecover。
- 非 ROOT 路径（session/executor）逐笔强制 `to != address(this) && to != address(0)`。
- 模块一律 `CALL`，绝不 `DELEGATECALL`；`onUninstall` 包 `try/catch`；validator 与 executor 映射隔离。
- 每个签名 digest 经 EIP-712 绑定 `chainId + address(this) + nonce`；P256 与 secp256k1 均强制 low-s。
- 持久状态必须放在 ERC-7201 命名空间（`my7702.account.v1`），勿用裸槽位。

## 注意 / Notes

- 注释为中英双语 / comments are bilingual (Chinese + English).
- `test/vendor/P256Verifier.sol` 仅测试用（本地 prague 无 0x100，需 etch）；`src/` 保持零三方依赖。
- 改动后务必 `forge fmt && forge test`；新增安全相关逻辑请补对抗性测试（见 `test/Security.t.sol`）。
- MegaETH 的 `0x100` 预编译未被官方确认，依赖 passkey 前先上链探测（见 README）。
