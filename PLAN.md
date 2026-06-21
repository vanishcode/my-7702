# my-7702 — 最小化 EIP-7702 智能账户实现计划

> 一个最小、依赖极少、安全优先的 EIP-7702 委托合约（delegate singleton）。
> EOA 通过 type-4 授权把代码委托到本合约，从而获得：批量执行、Passkey(P256/WebAuthn) 验证、Session Key、可装卸的插件模块系统。
> **不使用任何 ERC-4337 概念**（无 relay / bundler / paymaster / EntryPoint / UserOp）。

---

## 0. 已确认的决策（来自需求方）

| # | 决策点 | 选择 | 影响 |
|---|--------|------|------|
| D1 | Passkey 验证方式 | **完整 on-chain WebAuthn 解析** | 需解析 `authenticatorData` / `clientDataJSON` / base64url challenge / UP·UV 标志，可用真实设备 passkey（Touch ID / Face ID / Android / FIDO2） |
| D2 | Passkey 与 Session 的形态 | **做成可安装/卸载的 validator 插件** | 二者不编进核心，而是作为 type-1 模块，端到端演示插件系统 |
| D3 | 插件系统支持的模块类型 | **validator(1) + executor(2) + hook(4)** | 完整模块系统；executor 是盗资金高危面，需严格隔离 |
| D4 | 注释 / NatSpec 语言 | **中英双语** | 关键逻辑中英对照 |

> 说明：选了「完整 WebAuthn」+「全模块系统」后，规模已超出最朴素的「minimal」，但这是为了真实可用 + 完整演示插件系统。实现上仍逐文件保持精简，并按里程碑分阶段交付（见 §13）。

### 一个必须澄清的前提（如有异议请指出）
Session / Passkey 的执行天然需要一个**提交者（submitter）**把携带签名的交易发上链：
- **Passkey**：P256 公钥不是以太坊密钥，永远不可能是 `tx.origin`，所以必须由某个地址替它发交易；
- **Session key**：通常由 session key 持有者自己发交易、自付 gas。

这**不是** 4337 的 relay/bundler/paymaster——只是一笔携带签名的普通交易，gas 由发起者自付，链上无任何代付/打包基础设施。
而 EOA 本人的批量（`wallet_sendCalls`）走的是纯自发路径 `msg.sender == address(this)`，不需要签名。

---

## 1. 背景与设计依据（驱动设计的关键事实）

EIP-7702（Pectra，2025-05 上线）核心机制与安全要点（均经 web 调研确认，来源见 §15）：

- **委托指示器（delegation designator）**：type-4 `SET_CODE_TX` 把 EOA 的 code 设为 23 字节 `0xef0100 || <20字节地址>`。所有取码执行的操作都会加载并在 **EOA 自身的存储上下文**中运行被指向合约的代码。`address(this) == EOA`。
- **授权元组**：`[chain_id, address, nonce]`，由 EOA 的 secp256k1 私钥签 `keccak256(0x05 || rlp([chain_id,address,nonce]))`。`chain_id` 必须等于当前链或为 0；0 表示全链通用（跨链重放面更大）。→ **本项目固定 `chain_id = 6343`（chain-bound）**。
- **执行上下文**：EOA 自发交易时 `tx.origin == msg.sender == address(this)`；**任何第三方都能调用已委托的 EOA 代码**——所以任何「对外可达且无鉴权」的函数就是盗号入口（**头号越权面**）。
- **无构造函数**：委托安装的是已部署 runtime code，constructor 不会为 EOA 运行。独立的 `initialize()` 可被抢跑 → 初始化参数必须用 EOA 密钥签名，或与委托同一笔原子完成。
- **存储碰撞**：重新委托到另一合约**不会清空/迁移**旧存储；新合约会以自己的布局误读旧槽位 → **必须用 ERC-7201 命名空间存储**。
- **7702 打破的旧假设**（审计共识）：被委托 EOA 现在 `extcodesize>0`、可有 fallback、可重入 → 不能再用 `tx.origin==msg.sender` 或 extcodesize 判断 EOA；必须用真正的重入锁 + checks-effects-interactions。
- **P256 预编译**：RIP-7212 / EIP-7951（已 Final，Fusaka 上线）地址均为 `0x...0100`，输入 160 字节 `[hash,r,s,qx,qy]`，**失败返回空 returndata（非 32 字节 0）**——必须把「空 returndata」当作无效（footgun）。预编译**不强制 low-s**，需合约自检 `s <= n/2`。
- **SHA-256 预编译 `0x02`** 始终可用（WebAuthn 需要）。**EIP-1153 transient storage** 在 prague 可用（用作重入锁）。
- **MegaETH 测试网**：chain 6343、继承 OP-Isthmus/Prague、**支持 7702**；但其官方预编译文档**未显式列出 `0x100`** → **P256 预编译可用性未确认，必须先上链探测**（见 §12）。

---

## 2. 总体架构

```
                    ┌──────────────────────────────────────────────┐
   EOA (7702) ──▶   │            Account.sol  (delegate singleton)   │
   委托到本合约      │  immutable / 非 proxy / 非 upgradeable          │
                    │                                                │
   wallet_sendCalls │  ERC-7821  execute(bytes32 mode, bytes data)   │
   ───────────────▶ │   ├─ mode id1: 自发批量 (msg.sender==self)      │
                    │   └─ mode id2: opData 签名批量                  │
                    │                                                │
   dApp 验签        │  ERC-1271  isValidSignature(hash, sig)         │
   ───────────────▶ │                                                │
                    │  模块注册表 (ERC-7579 子集, self-gated)          │
                    │   installModule / uninstallModule / isInstalled│
                    │   validators[] / executors[] / hooks[]         │
                    │                                                │
                    │  内置 ROOT validator = ecrecover==address(this)│
                    │  nonce / EIP-1153 重入锁 / ERC-7201 storage     │
                    └───────┬───────────────┬──────────────┬─────────┘
                            │ CALL          │ CALL         │ CALL
                   ┌────────▼───┐   ┌────────▼─────┐  ┌─────▼──────┐
                   │ Validator  │   │  Executor    │  │   Hook     │
                   │ (type 1)   │   │  (type 2)    │  │  (type 4)  │
                   │ ·WebAuthn  │   │ executeFrom- │  │ pre/post   │
                   │ ·SessionKey│   │ Executor 回调 │  │  Check     │
                   └────────────┘   └──────────────┘  └────────────┘
```

### 鉴权优先级（单一执行入口收敛）
1. **ROOT（最高权）** —— `msg.sender == address(this)`（mode1 自发） 或 opData 中 `ecrecover(execHash, sig) == address(this)`（relayed root）。**唯一允许 self-call（即可达 admin 选择器）的路径。**
2. **Validator 模块** —— session / passkey：opData 路由到已安装的 type-1 模块校验。**禁止 self-call**。
3. **Executor 模块** —— 已安装 type-2 模块回调 `executeFromExecutor`。**禁止 self-call**。
4. Hook 模块在执行前后包裹 `preCheck/postCheck`（不能授权，只能放行/拦截）。

> **核心安全不变式**：只有 ROOT 路径 `allowSelfCall = true`；session / executor 路径 `allowSelfCall = false`，逐笔强制 `call.to != address(this) && call.to != address(0)`（ERC-7821 把 `address(0)` 归一为 `address(this)`，必须一并拦）。这条规则是防 session/executor 越权调用 admin 的**最关键防线**。

---

## 3. 存储布局（ERC-7201 命名空间）

核心存储置于唯一命名空间根槽，避免重委托碰撞：
`keccak256(abi.encode(uint256(keccak256("my7702.account.v1")) - 1)) & ~bytes32(0xff)`

```solidity
struct AccountState {
    uint256 nonce;                              // opData 签名路径的重放守卫（顺序递增）
    mapping(address => bool) validators;        // type 1 模块集合
    mapping(address => bool) executors;         // type 2 模块集合
    address[] hooks;                            // type 4 模块（有序，执行前后调用）
    mapping(address => bool) isHook;            // 去重 / O(1) 查询
}
// EIP-1153 重入锁用独立 transient slot（tstore/tload），逐交易自动清零。
```

模块各自的业务状态（passkey 公钥、session 策略）**存在各模块合约自身存储里、以账户地址为 key**（ERC-7579 singleton 模块标准模型）。模块被账户 `CALL` 调用时 `msg.sender == 账户地址`，因此模块天然可用 `msg.sender == account` 做 root 门禁来配置策略。

---

## 4. 核心合约接口（`src/Account.sol`）

```solidity
// ---- ERC-7821 批量执行 ----
function execute(bytes32 mode, bytes calldata executionData) external payable;
function supportsExecutionMode(bytes32 mode) external view returns (bool);

// ---- ERC-1271 ----
function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4);

// ---- 模块注册表 (ERC-7579 子集) ----
function installModule(uint256 typeId, address module, bytes calldata initData) external; // onlySelf
function uninstallModule(uint256 typeId, address module, bytes calldata deInitData) external; // onlySelf
function isModuleInstalled(uint256 typeId, address module, bytes calldata ctx) external view returns (bool);

// ---- Executor 回调入口 ----
function executeFromExecutor(bytes32 mode, bytes calldata executionData)
    external returns (bytes[] memory returnData); // onlyInstalledExecutor + 禁 self-call

// ---- 读取 ----
function getNonce() external view returns (uint256);

event ModuleInstalled(uint256 typeId, address module);
event ModuleUninstalled(uint256 typeId, address module);
```

### Call 与 mode 编码（沿用 Solady/ERC-7821 常量）
```solidity
struct Call { address to; uint256 value; bytes data; } // to==address(0) → address(this)（仅 ROOT 路径放行）
// mode bytes32: [0]=CALLTYPE(0x01 batch) [1]=EXECTYPE(0x00 revert-on-fail)
//   [6..9]=selector: 0x00000000 → id1(无 opData); 0x78210001 → id2(带 opData)
// 不支持的 mode → revert UnsupportedExecutionMode()
// executionData: id1 = abi.encode(Call[]); id2 = abi.encode(Call[], bytes opData)
// opData = abi.encode(address validator, bytes sig)   // validator==address(this) 视为 ROOT/ecrecover
```

### `execute` 控制流（伪代码）
```
reentrancyGuard {
  (callType, execType, modeId) = decode(mode)
  hooksData = _preHooks(msg.sender, msg.value, msg.data)

  if modeId == 1:                       // 自发批量
     require(msg.sender == address(this))   // ROOT
     calls = decode(executionData); allowSelfCall = true
  else if modeId == 2:                  // 签名批量
     (calls, opData) = decode(executionData)
     (validator, sig) = decode(opData)
     callsHash = keccak256(encode(calls))
     execHash  = _domainHash(block.chainid, address(this), state.nonce, callsHash) // EIP-712
     if validator == address(this):     // ROOT (relayed)
         require(_recoverChecked(execHash, sig) == address(this)); allowSelfCall = true
     else:                              // 模块鉴权 (session / passkey)
         require(state.validators[validator])
         require(IValidator(validator).validateExecution(execHash, executionData, sig))
         allowSelfCall = false
     state.nonce += 1                   // checks-effects-interactions：先消费 nonce 再外呼
  else: revert UnsupportedExecutionMode()

  _executeCalls(calls, allowSelfCall)   // 逐笔 CALL；非 ROOT 路径强制 to != self/0
  _postHooks(hooksData)
}
```

`isValidSignature`：先尝试 `ecrecover(hash,sig)==address(this)`（ROOT，解决「7702 EOA 有 code 导致 dApp 跳过 ecrecover」问题）；否则把 `sig` 解码为 `(validator, innerSig)` 路由到已安装 validator 的 `validateSignature`。命中返回 `0x1626ba7e`，否则 `0xffffffff`。

---

## 5. 模块接口（`src/interfaces/IERC7579Modules.sol`）

```solidity
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR  = 2;
uint256 constant MODULE_TYPE_HOOK      = 4;

interface IModule {
    function onInstall(bytes calldata data) external;
    function onUninstall(bytes calldata data) external;
    function isModuleType(uint256 typeId) external view returns (bool);
}

interface IValidator is IModule {
    // 账户已算好 execHash（绑定 chainId+account+nonce+callsHash）。
    // executionData 让 session 类逐笔校验策略；passkey 类可只验签。view：策略只读，nonce 由核心消费。
    function validateExecution(bytes32 execHash, bytes calldata executionData, bytes calldata sig)
        external view returns (bool);
    // ERC-1271 风格消息验签（供核心 isValidSignature 路由）。
    function validateSignature(bytes32 hash, bytes calldata sig) external view returns (bool);
}

interface IExecutor is IModule {} // 仅靠 account.executeFromExecutor 回调，无额外方法

interface IHook is IModule {
    function preCheck(address sender, uint256 value, bytes calldata data)
        external returns (bytes memory hookData);
    function postCheck(bytes calldata hookData) external;
}
```

---

## 6. 功能详细设计

### 6.1 批量执行（EIP-5792 `wallet_sendCalls` 兼容）
- 链上落点即 ERC-7821 `execute(bytes32,bytes)`，正是 MetaMask / viem / Solady 的目标接口，天然兼容 `wallet_sendCalls`。
- 原子性：`EXECTYPE=0x00`，任一子调用失败即冒泡 revert（满足 `atomicRequired=true`；钱包对 `atomicRequired=false` 自行拆分）。
- 不实现 id3（batch-of-batches）与 try 模式，保持精简。

### 6.2 Passkey / WebAuthn validator（`src/modules/WebAuthnValidator.sol`，type 1）
- 存储：`mapping(address account => P256Key{bytes32 x; bytes32 y; bool set})`（可扩展为多 key + keyId）。
- 注册/轮换：账户调用模块（`msg.sender==account`，root 门禁）设置/更换公钥；初次注册须经 ROOT 路径（自发或 root 签名），杜绝抢跑。
- `validateExecution(execHash, _, sig)`：把 `execHash` 作为 WebAuthn **challenge**：
  1. `sig` 解码为 `(authenticatorData, clientDataJSON, r, s, challengeIndex, typeIndex)`；
  2. 校验 `clientDataJSON` 中 `"type":"webauthn.get"`；
  3. base64url 编码 `execHash` 并校验其出现在 `clientDataJSON` 的 `"challenge":"..."`；
  4. 校验 `authenticatorData` flags：UP(bit0) 必置；UV(bit2) 可选（按 `requireUV` 配置）；
  5. `msgHash = sha256(authenticatorData || sha256(clientDataJSON))`（用 `0x02` 预编译）；
  6. `P256.verify(msgHash, r, s, x, y)` → 经 `0x100`，强制 low-s、拒 `r/s==0`、**空 returndata 视为无效**。
- `validateSignature(hash, sig)`：同 5–6，把 `hash` 当 challenge，供 ERC-1271。

### 6.3 Session Key validator（`src/modules/SessionKeyValidator.sol`，type 1）
- 存储：`mapping(address account => mapping(address sessionKey => Policy))`
  ```solidity
  struct Policy {
      uint64 validAfter;          // 0 = 立即生效
      uint64 validUntil;          // 0 = 永不过期
      uint128 perCallEthCap;      // 每笔 ETH 上限
      // 允许的 (target, selector) 组合：内联数组（最小、可审计）
      address[] targets;
      bytes4[]  selectors;
      bool exists;
  }
  ```
- 安装/撤销：账户调用模块（`msg.sender==account`）`installSession/revokeSession`。撤销 = `delete` 映射（即时，且使在途签名因 `exists==false` 失效）+ 被动过期。
- `validateExecution(execHash, executionData, sig)`：
  1. `decode(executionData) → (calls, opData)`；`opData` 携带 `sessionKey`（或由 sig 直接 `ecrecover` 出 sessionKey）；
  2. `ecrecover(execHash, sig) == sessionKey` 且 `policy.exists`；
  3. 时间窗 `validAfter <= now <= validUntil`；
  4. **逐笔**校验：`call.to != account && call.to != address(0)`（核心层也会再拦一次，双保险）、`call.to ∈ targets`、`bytes4(call.data) ∈ selectors`、`call.value <= perCallEthCap`。
- 仅做 per-call 上限（无状态、便宜）；累计预算（cumulative budget）作为后续可选项（见 §14）。

### 6.4 插件系统（validator / executor / hook，可自行装卸）
- **安装/卸载门禁**：`installModule/uninstallModule` 仅 `msg.sender == address(this)`（即只能经 ROOT 路径）；杜绝公开可调的 install。
- **调用方式**：对模块一律 `CALL`，**绝不 `DELEGATECALL`**（delegatecall 模块=全账户沦陷）。
- **卸载健壮性**：`onUninstall` 包 `try/catch`，无论回调是否 revert 都从集合移除——防恶意模块「拒卸自锁」。
- **重入**：`install/uninstall` 也加重入锁（`onInstall/onUninstall` 可能回调账户）。
- **Executor（type 2，高危）**：通过 `executeFromExecutor` 回调，`onlyInstalledExecutor`；**禁 self-call/zero**，防止已装 executor 路由到 `installModule` 等 admin 选择器实现越权。validators 与 executors 用**独立映射**，确保 validator 永不能被当 executor 调用（ERC-7579 明确告警）。
- **Hook（type 4）**：核心在 `execute`/`executeFromExecutor` 前后顺序调用 `preCheck/postCheck`；hook 不能授权，只能放行或 revert 拦截。注意恶意/有 bug 的 hook 可致 DoS——hook 由 ROOT 安装，属可信，但文档须标注此风险。
- **演示模块**（证明 type 2/4 闭环，主要用于测试/示例）：
  - `src/modules/SpendingLimitHook.sol`（type 4）：`preCheck` 强制单笔 ETH 支出上限。
  - `src/modules/ExampleExecutor.sol`（type 2）：经 `executeFromExecutor` 执行一笔预设动作（如转账），用于测试 executor 路径。

---

## 7. 安全设计（威胁 → 缓解）

| 威胁 | 缓解 |
|------|------|
| **越权（头号面）**：委托后任何人可调本合约代码 | 所有特权/admin 函数 `require(msg.sender==address(this))`；默认拒绝，无公开 install/exec 入口 |
| **Session/Executor 越权打 admin** | 非 ROOT 路径 `allowSelfCall=false`，逐笔禁 `to==self/zero`；admin 选择器仅 ROOT 可达 |
| **初始化抢跑**（无 constructor） | passkey/session 等配置须经 ROOT（自发 或 EOA 签名绑定 `address(this)`+nonce），或与委托同一笔原子完成 |
| **重委托存储碰撞/擦除** | ERC-7201 命名空间存储；immutable singleton（非 proxy，无降级）；每个签名 digest 绑定 nonce+chainId+address(this)，旧签名无法授权别的动作 |
| **签名可塑性重放**（P256 不强制 low-s；secp256k1 需 `s<=n/2`） | 两条曲线均在合约内强制 low-s、拒 `r/s==0`；digest 一次性（nonce） |
| **P256 预编译空 returndata footgun** | 成功 ≡ `call ok && returndatasize==32 && word==1`；空=无效 |
| **重入**（7702 EOA 可有 fallback） | EIP-1153 transient 重入锁 + checks-effects-interactions（外呼前先 `nonce+=1`） |
| **恶意模块** | 仅 `CALL` 不 `DELEGATECALL`；install/uninstall self-gated + 重入锁；`onUninstall` try/catch 必移除；executor 与 validator 映射隔离 |
| **跨链重放** | chain-bound 授权（chainId 6343）；EIP-712 domain 绑定 `block.chainid` + `address(this)` |
| **dApp 验签跳过 ecrecover**（EOA 现有 code） | `isValidSignature` 显式 ecrecover 回退到 EOA 地址 + 模块路由 |

---

## 8. 文件结构

```
src/
  Account.sol                      # 核心 delegate singleton
  interfaces/
    IERC7579Modules.sol            # IModule / IValidator / IExecutor / IHook + 类型常量
    IERC1271.sol
  lib/
    AccountStorage.sol             # ERC-7201 命名空间 + AccountState 访问器
    ModeLib.sol                    # ERC-7821 mode 编解码（极小，可内联）
    ExecutionLib.sol               # Call[] 编解码（可内联）
    P256.sol                       # 0x100 预编译调用 + low-s + 零值检查 (+ 可选 verifier 回退)
    Base64Url.sol                  # 最小 base64url 编码（仅 challenge 匹配用）
    WebAuthn.sol                   # WebAuthn assertion 解析（用 P256 + sha256 + Base64Url）
  modules/
    WebAuthnValidator.sol          # type 1：per-account P256 公钥 + WebAuthn 验签
    SessionKeyValidator.sol        # type 1：per-account session 策略 + 验签 + 逐笔策略
    SpendingLimitHook.sol          # type 4：示例 hook（单笔 ETH 上限）
    ExampleExecutor.sol            # type 2：示例 executor（测试 executor 路径）
script/
  Deploy.s.sol                     # CREATE2 部署 Account + 各模块（确定性地址）
  Delegate.s.sol                   # 为 EOA 签发并附加 7702 委托（演示/烟测）
test/
  Account.t.sol                    # 批量 / ERC-1271 / 模块装卸 / mode 编解码
  P256.t.sol                       # 已知正/负向量、low-s、空 returndata
  WebAuthnValidator.t.sol          # 真实 WebAuthn assertion 向量
  SessionKeyValidator.t.sol        # 作用域 / 过期 / 撤销 / 越权尝试
  Security.t.sol                   # 对抗性：越权、重放、重入、self-call 拦截、恶意模块拒卸
foundry.toml
PLAN.md  README.md  AGENTS.md
```

> 生产 `src/` **零第三方依赖**（仅手写库）；`forge-std` 仅 dev/test。详见 §14 关于 WebAuthn 手写与否的待确认项。

---

## 9. MegaETH 测试网：配置与部署

**网络事实（已调研）**：chain id `6343`（hex `0x18c7`；旧链 `6342` 已废弃勿用）；币 ETH/18；公共 RPC `https://carrot.megaeth.com/rpc`；浏览器 Blockscout `https://megaeth-testnet-v2.blockscout.com/`；水龙头 `https://testnet.megaeth.com`（≤0.005 ETH/地址/24h）；**支持 7702**；**双 gas 模型**（普通转账≈60k gas），7702 交易要给足 `--gas-limit`。

### `foundry.toml`
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.28"
evm_version = "prague"     # 7702 type-4 codegen + signDelegation/attachDelegation 必需
optimizer = true
optimizer_runs = 200

[rpc_endpoints]
megaeth_testnet = "https://carrot.megaeth.com/rpc"

[etherscan]
megaeth_testnet = { key = "any", url = "https://megaeth-testnet-v2.blockscout.com/api/", chain = 6343 }
```

### 部署与委托（cast / forge）
```bash
# 0) 确认链 id（防误连废弃的 6342）
cast chain-id --rpc-url megaeth_testnet            # 期望 6343

# 1) 探测 P256 预编译 0x100（关键！见 §12）—— 用已知正向量，期望返回 32 字节 0x..01
cast call 0x0000000000000000000000000000000000000100 <160字节正向量> --rpc-url megaeth_testnet

# 2) 部署实现合约与模块
forge script script/Deploy.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast

# 3) 把 EOA 委托到 Account（cast 自动为该 EOA 签授权）
cast send --rpc-url megaeth_testnet --private-key $PRIVATE_KEY \
  --auth <ACCOUNT_ADDR> $EOA <execute calldata> --gas-limit 3000000

# 4) 验证合约
forge verify-contract --rpc-url megaeth_testnet --verifier blockscout \
  --verifier-url https://megaeth-testnet-v2.blockscout.com/api/ <addr> src/Account.sol:Account
```

Foundry 测试用 `vm.signAndAttachDelegation(impl, eoaPk)`（forge 1.7.1 已确认含 7702 cheatcodes），chain-bound 用 `crossChain=false`。

---

## 10. 测试计划（Foundry）

- **单元/集成**：mode1 自发批量；mode2 root-ecrecover 批量；ERC-1271 root + 模块路由；模块 install/uninstall/isInstalled（三类型）；nonce 递增与重放拒绝。
- **P256/WebAuthn**：链下用 WebAuthn 标准向量（或 Solady/Daimo 测试向量）喂入 `WebAuthnValidator`，覆盖合法、错误 challenge、缺 UP 标志、错 type、high-s 拒绝、空 returndata。
- **Session**：时间窗、target/selector/value 作用域命中与越界拒绝、撤销即时失效、过期。
- **对抗性（`Security.t.sol`，重点）**：
  - session/executor 尝试 `to==address(this)` 或 `address(0)` 打 `installModule`/转移控制 → 必拒；
  - 重放同一 opData（nonce 已消费）→ 必拒；
  - 重入 `execute` → 锁拦截；
  - 恶意模块 `onUninstall` revert → 仍被移除；
  - 非 ROOT 调 `installModule` → 必拒；
  - high-s 可塑签名 → 必拒。
- CI 已有（fmt + build --sizes + test -vvv）；保持 `forge fmt` 通过、关注合约字节码体积。

---

## 11. 实现里程碑（分阶段交付）

| 阶段 | 内容 | 产出 |
|------|------|------|
| **M0** | `foundry.toml` + ERC-7201 存储 + ERC-7821 mode1 自发批量 + ERC-1271 root + 模块注册表骨架 | 可自发批量、可装卸空模块 + 单测 |
| **M1** | opData(mode2) 路径 + 内置 ROOT ecrecover validator + nonce + EIP-1153 重入锁 | relayed root 批量 + 重放/重入测试 |
| **M2** | `SessionKeyValidator`（装卸/验签/逐笔策略/撤销）+ self-call 拦截不变式 | session 全流程 + 对抗测试 |
| **M3** | `P256.sol` + `Base64Url.sol` + `WebAuthn.sol` + `WebAuthnValidator`；**先上链探测 0x100** | passkey 全流程 + WebAuthn 向量测试 |
| **M4** | Executor + Hook 支持 + `ExampleExecutor` + `SpendingLimitHook` | 插件系统三类型闭环 + 测试 |
| **M5** | `Deploy.s.sol` / `Delegate.s.sol` + MegaETH 测试网部署 + 链上烟测（委托/批量/session/passkey） | 测试网可用 + README 使用说明 |

---

## 12. ⚠️ 阻塞性技术风险：MegaETH 的 P256 预编译

WebAuthn/passkey **强依赖** `0x100` 预编译。MegaETH 继承 OP-Isthmus（Fjord 起含该预编译），**很可能可用，但官方预编译文档未显式列出**。
**M3 第一步必须上链探测**（§9 步骤 1）。两种结果：
- **存在** → 直接用预编译，零依赖（首选）；
- **不存在** → 需引入一个已部署的 P256 verifier 回退（Daimo `0xc2b78104907F722DABAc4C69f826a522B2754De4` 或 Solady `0x000000000000D01eA45F9eFD5c54f037Fa57Ea1a`，同 160 字节接口；worst-case ~330k gas）——这会引入一个**外部依赖**。

> 这点我**不替你下结论**：若探测失败，是接受「部署/指向一个外部 verifier 合约」，还是「该测试网上暂不启用 passkey、仅 secp256k1+session」？届时会带探测结果来问你。

---

## 13. 待确认的实现选项（非阻塞，实现/评审时定，列此请你过目）

1. **WebAuthn 手写 vs 借用审计文件**：你要求「减少三方库依赖」，默认**手写**精简 `P256.sol`/`WebAuthn.sol`（src 零依赖）。但手写密码学相邻解析有审计风险——**安全更稳的替代**是 vendor 单文件审计实现（Solady `P256`/`WebAuthnP256` 或 Daimo）。**默认手写 + 用真实向量重测**；若你更看重安全可改为 vendor。
2. **nonce 模型**：默认**单账户顺序 nonce**（最简）。多 session 并发提交会争用；如需并行可改 2D nonce(`key||seq`)。
3. **Session 允许列表表示**：默认**内联 `(target,selector)` 数组**（可审计）。目标很多时可换 Merkle root（省安装 gas，但调用方需带 proof）。
4. **接收回调**：是否实现 `onERC721Received`/`onERC1155Received`/`receive()`？默认实现 `receive()`（收 ETH）+ 两个 NFT 接收回调（智能账户常见预期）。如要更小可去掉。
5. **Session 累计预算（cumulative budget）**：默认**不做**（仅 per-call 上限）；如需「整段会话最多花 X」再加有状态计数器。

---

## 14. 安全审计与修复 / Security audit & remediation

实现完成后做了一轮**对抗式多代理安全审计**（6 维度发现 → 逐条对抗式证伪 → 综合），再对修复做了一轮**对抗式复核**。结论：4 项修复全部完整、未引入新问题、7 条不变式仍成立——**可上测试网**。

After implementation, an **adversarial multi-agent audit** (6 dimensions → adversarially refute each → synthesize) ran, followed by an adversarial **re-verification of the fixes**. Verdict: all fixes complete, no new issues, invariants hold — **ship to testnet**.

| # | 严重度 | 问题 | 修复 | 回归测试 |
|---|--------|------|------|----------|
| 1 | **Critical** | executor/session 可驱动账户去调已装模块的配置项（`setPassKey`/`installSession`）越权接管 | 非 ROOT 路径在 `_executeCalls` 拒绝 `to==self` **或任何已安装模块**（`ModuleTargetNotAllowed`），一处堵住两条路径 | `test_Executor_CannotConfigureModule`, `test_Session_CannotTargetInstalledModule` |
| 2 | **High** | ERC-1271 消息签名可被重放为执行授权 | 消息先用 `PersonalSign` typehash 包裹，与 `EXECUTE_TYPEHASH` 不相交 | `test_ERC1271_DomainSeparation` |
| 3 | **High** | 执行期间增删 hook 导致 `_postHooks` 越界/错配 DoS | `_preHooks` 快照 hook 地址与数据，`_postHooks` 遍历快照 | 现有 hook 测试 |
| 4 | **Medium** | `SpendingLimitHook` 校验 `msg.value` 而非实际 `calls[i].value`，上限形同虚设 | hooks 改为接收 `Σ calls[i].value`（真实转出额） | `test_Hook_BlocksOverLimit` |
| 5 | Low | `isValidSignature` 对畸形签名 revert 而非返回 FAIL | 长度判断 + `try/catch` 兜底返回 `0xffffffff` | `test_ERC1271_MalformedReturnsFail` |
| 6 | Info | `supportsInterface` 漏报 ERC-1155 receiver id | 补 `0x4e2312e0` | — |

**审计已证伪（非问题）/ refuted by the audit**：execHash 缺 validator 地址（各路径独立从签名重导权限 + 全局 nonce CEI）、WebAuthn `challengeIndex/typeIndex` 由调用者提供（needle 两端定界、base64url 字母表不含 `"`，无法值混淆）、install/uninstall 缺 `nonReentrant`（`onlySelf` + 模块无法回到 admin，且故意如此以免与 execute 锁死锁）、WebAuthn 不校验 rpIdHash/origin（链上不可验，安全来自 challenge=execHash 的链/账户/nonce 绑定）。

**已知的设计性残留（非 bug，已在 §13 标注）/ known by-design residuals**：`SessionKeyValidator.perCallEthCap` 与 `SpendingLimitHook` 都是**单笔**上限而非**累计预算**；spend hook 仅约束 ETH 毛额、不含 ERC-20。若需总额上限，按 §13(5) 增加累计计数器。

## 15. 参考资料（精选）

- EIP-7702 Set Code for EOAs — https://eips.ethereum.org/EIPS/eip-7702
- ethereum.org Pectra 7702 指南 — https://ethereum.org/roadmap/pectra/7702/
- EIP-7951 P256VERIFY（Final）— https://eips.ethereum.org/EIPS/eip-7951 ；RIP-7212 — https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md
- ERC-7821 Minimal Batch Executor — https://eips.ethereum.org/EIPS/eip-7821 ；Solady ERC7821 — https://github.com/Vectorized/solady/blob/main/src/accounts/ERC7821.sol
- ERC-7579 Minimal Modular Smart Accounts — https://eips.ethereum.org/EIPS/eip-7579
- EIP-5792 wallet_sendCalls — https://eips.ethereum.org/EIPS/eip-5792
- WebAuthn 链上验证：Daimo p256-verifier — https://github.com/daimo-eth/p256-verifier ；Base webauthn-sol — https://github.com/base/webauthn-sol ；Solady P256 — https://github.com/Vectorized/solady/blob/main/src/utils/P256.sol
- 7702 安全：Nethermind 攻击面 — https://www.nethermind.io/blog/eip-7702-attack-surfaces-what-developers-should-know ；CertiK — https://www.certik.com/blog/pectras-eip-7702-redefining-trust-assumptions-of-externally-owned-accounts ；Base 升级安全 — https://blog.base.dev/securing-eip-7702-upgrades
- 参考实现：Uniswap Calibur — https://github.com/Uniswap/calibur ；MetaMask EIP7702StatelessDeleGator — https://github.com/MetaMask/delegation-framework ；Openfort 7702（多签名方案）— https://github.com/openfort-xyz/openfort-7702-account
- MegaETH 文档：连接 — https://docs.megaeth.com/user-guide/connect

---

*生成时间：2026-06-21。本计划基于上述 web 调研与需求方决策（§0）。实现遵循「最小、低依赖、安全优先、不引入 4337」原则；遇到真正不确定处（尤其 §12）会先询问、不擅自下结论。*
