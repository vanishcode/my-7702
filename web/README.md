# my-7702 测试 dapp

最小化测试前端，演示 [`../src`](../src) 里 EIP-7702 智能账户的能力：

1. **7702 升级** — 一笔 type-4 交易把 EOA 委托到 `Account` 实现单例。
2. **插件商店** — ERC-7579 子集，validator(1)/executor(2)/hook(4) 三类模块自助装卸。
3. **Session Key** — 登记带作用域的临时密钥（目标白名单 + 单笔 ETH 上限 + 有效期），session key 只签名、burner EOA 提交；越界（超上限 / 白名单外 / 过期 / 撤销 / 触达账户自身）一律被链上 `validateExecution` 拒绝。
4. **Passkey 交易签名** — 用真实设备 passkey（Touch ID / Windows Hello / 安全密钥）的 P256/WebAuthn 断言授权一笔批量执行。
5. **单笔支出上限** — 更改 SpendingLimitHook(type-4) 的单笔 ETH 上限（账户重新调用 `onInstall(cap)` 覆盖），下一次 `execute` 的 `preCheck` 立即按新上限拦截。
6. **批量执行** — ERC-7821 自发批量 `execute(MODE_BATCH, abi.encode(Call[]))`：一笔交易原子执行多笔调用（任一笔失败则整批回滚），即 EIP-5792 `wallet_sendCalls` 的链上落点。

技术栈：Vite + React + TS · wagmi + viem · RainbowKit · Tailwind v4 + shadcn-ui · `ox`(WebAuthn)。

## 为什么用本地 burner 私钥而不是注入钱包做 7702

委托到**自定义合约**的 7702 授权签的是 `keccak256(0x05 ‖ rlp([chainId, address, nonce]))`——这不是 EIP-712，注入钱包（MetaMask 等）无法产出：`eth_signTypedData` 的 digest 不对，签任意 digest 需要已被弃用的 `eth_sign`，且 viem 的 `signAuthorization` 只支持本地账户。MetaMask 的 7702 只会委托到它自己白名单内的单例。

→ 所以本 dapp 用一个**浏览器内的 burner 私钥**做 7702 账户（viem `signAuthorization` 本地签名）。RainbowKit 连接的钱包用于「给测试账户充值」。**仅测试网，私钥只存在浏览器 localStorage。**

## 运行

```bash
pnpm install
pnpm dev        # http://localhost:5173
pnpm build      # tsc + vite 产物到 dist/
```

合约地址默认指向已部署到 MegaETH(6343) 的实例（见 `src/lib/contracts.ts`），可用 `.env` 覆盖（见 `.env.example`）。

## 流程

1. 「生成新测试账户」→ 领水龙头或用连接的钱包充值。
2. **① 7702 升级** → 升级到 Account。
3. **② 插件商店** → 装卸模块（用 session key 前需在此安装 SessionKeyValidator，调支出上限前需安装 SpendingLimitHook）。
4. **③ Session Key** → 生成 session key → 登记策略（目标 + 单笔上限 + 有效期）→ 用 session key 签名并提交；可改大金额或换地址观察越界被链上拒绝，或「撤销」即时失效。
5. **④ Passkey** → 注册 passkey（自动安装 WebAuthnValidator）→ 用 passkey 签名并提交一笔演示交易。
6. **⑤ 单笔支出上限** → 安装 SpendingLimitHook 后，在此更改单笔 ETH 上限；回到「⑥ 批量执行」发一笔超额转账即被 `SpendingLimitExceeded` 拦截。
7. **⑥ 批量执行** → 编辑若干笔 (target, value, data) 调用，「一笔发送（原子批量）」一次性提交（可「填充示例」快速试两笔自转账）。
