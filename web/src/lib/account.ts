import {
  createPublicClient,
  createWalletClient,
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  http,
  serializeSignature,
  type Address,
  type Hex,
} from "viem";
import {generatePrivateKey, privateKeyToAccount, sign} from "viem/accounts";
import {megaethTestnet} from "./chain";
import {
  ADDR,
  accountAbi,
  callTupleArrayParam,
  MODE_BATCH,
  MODE_BATCH_OPDATA,
  sessionAbi,
  spendingHookAbi,
  webauthnAbi,
  type ModuleType,
} from "./contracts";
import type {EncodedWebAuthnAuth} from "./passkey";

/** 共享只读客户端 / shared read-only client. */
export const publicClient = createPublicClient({chain: megaethTestnet, transport: http()});

/** 一笔 ERC-7821 调用 / a single ERC-7821 call. */
export interface Call {
  target: Address;
  value: bigint;
  data: Hex;
}

/** SessionKeyValidator.Policy 的镜像（字段顺序须与 Solidity 一致）/ mirrors SessionKeyValidator.Policy. */
export interface SessionPolicy {
  validAfter: number; // uint48（viem 解码为 number），0 = 立即生效 / 0 = active now
  validUntil: number; // uint48（viem 解码为 number），0 = 永不过期 / 0 = never expires
  perCallEthCap: bigint; // 每笔 value 上限 / per-call ETH cap
  targets: readonly Address[]; // 允许的目标（空 = 拒绝一切）/ allowed targets (empty = deny all)
  selectors: readonly Hex[]; // 允许的 bytes4 选择器（空 = 通配）/ allowed selectors (empty = wildcard)
  exists: boolean;
}

function walletOf(pk: Hex) {
  const account = privateKeyToAccount(pk);
  const wallet = createWalletClient({account, chain: megaethTestnet, transport: http()});
  return {account, wallet};
}

// ───────────────────────── burner 私钥存储 / burner key storage ─────────────────────────

const PK_KEY = "my7702.burner.pk";

export function loadPk(): Hex | null {
  const v = localStorage.getItem(PK_KEY);
  return v && /^0x[0-9a-fA-F]{64}$/.test(v) ? (v as Hex) : null;
}
export function savePk(pk: Hex) {
  localStorage.setItem(PK_KEY, pk);
}
export function clearPk() {
  localStorage.removeItem(PK_KEY);
}
export function newPk(): Hex {
  return generatePrivateKey();
}
export function addrOf(pk: Hex): Address {
  return privateKeyToAccount(pk).address;
}

// ───────────────────────── 7702 委托状态 / delegation status ─────────────────────────

/** 读 EOA 的委托目标；未委托返回 null / read the EOA delegation target, or null. */
export async function getDelegation(address: Address): Promise<Address | null> {
  const code = await publicClient.getCode({address});
  if (!code || code === "0x") return null;
  if (code.length === 48 && code.slice(2, 8).toLowerCase() === "ef0100") {
    return getAddress(("0x" + code.slice(8, 48)) as Hex);
  }
  return null;
}

/**
 * 7702 升级：把 EOA 的 code 委托到 Account 实现。
 * authorization 签的是 keccak256(0x05 ‖ rlp([chainId,address,nonce]))——本地私钥直接签，再发交易。
 * Delegate the EOA to the Account impl. executor:'self' 让 viem 用 nonce+1 签授权。
 */
export async function delegate(pk: Hex): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  const authorization = await wallet.signAuthorization({
    account,
    contractAddress: ADDR.accountImpl,
    executor: "self",
  });
  return wallet.sendTransaction({
    authorizationList: [authorization],
    to: account.address,
    data: "0x",
    gas: 1_000_000n, // MegaETH 双 gas 模型，7702 交易给足上限 / generous gas for the 7702 tx
  });
}

/** 撤销委托：把 code 重新指向 address(0) / revoke delegation by pointing code at the zero address. */
export async function undelegate(pk: Hex): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  const authorization = await wallet.signAuthorization({
    account,
    contractAddress: "0x0000000000000000000000000000000000000000",
    executor: "self",
  });
  return wallet.sendTransaction({
    authorizationList: [authorization],
    to: account.address,
    data: "0x",
    gas: 1_000_000n,
  });
}

// ───────────────────────── 自发批量执行 / self-batch (ERC-7821 id1, ROOT) ─────────────────────────

/**
 * 自发批量：EOA 给自己发一笔 execute(MODE_BATCH, abi.encode(Call[]))，一笔交易里原子执行多笔调用——
 * 任一笔失败则整批回滚（EXECTYPE = revert-on-failure）。走 ROOT 路径 msg.sender == address(this)，无需签名。
 * 这正是 EIP-5792 `wallet_sendCalls` 的链上落点；转出的 ETH 由账户自身余额支付，无需随交易带 value。
 * Self-batch: the EOA self-sends one execute(MODE_BATCH, Call[]); all calls run atomically (all-or-nothing).
 * ROOT path (msg.sender == address(this)), no signature — the on-chain target of wallet_sendCalls.
 */
export async function sendBatch(pk: Hex, calls: Call[]): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({
      abi: accountAbi,
      functionName: "execute",
      args: [MODE_BATCH, encodeAbiParameters([callTupleArrayParam], [calls])],
    }),
  });
}

// ───────────────────────── 模块系统 / module registry ─────────────────────────

export async function isModuleInstalled(account: Address, typeId: ModuleType, module: Address): Promise<boolean> {
  return publicClient.readContract({
    address: account,
    abi: accountAbi,
    functionName: "isModuleInstalled",
    args: [BigInt(typeId), module, "0x"],
  });
}

/** ROOT 路径：EOA 给自己发交易调 installModule（msg.sender==address(this)）/ self-tx install. */
export async function installModule(pk: Hex, typeId: ModuleType, module: Address, initData: Hex): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({
      abi: accountAbi,
      functionName: "installModule",
      args: [BigInt(typeId), module, initData],
    }),
  });
}

export async function uninstallModule(pk: Hex, typeId: ModuleType, module: Address): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({
      abi: accountAbi,
      functionName: "uninstallModule",
      args: [BigInt(typeId), module, "0x"],
    }),
  });
}

// ───────────────────────── passkey 公钥注册 / passkey registration ─────────────────────────

/** 读取已注册的 passkey 公钥是否存在 / whether a passkey is registered on-chain. */
export async function getPassKeySet(account: Address): Promise<boolean> {
  const r = await publicClient.readContract({
    address: ADDR.webauthnValidator,
    abi: webauthnAbi,
    functionName: "passKeys",
    args: [account],
  });
  return r[3]; // set
}

/**
 * 把 passkey 公钥写到 WebAuthnValidator。
 * 若验证器未安装：installModule(1, webauthn, abi.encode(x,y,uv)) 安装并原子设置；
 * 若已安装：execute(MODE_BATCH, [setPassKey]) 自发批量设置（msg.sender==account）。
 */
export async function registerPassKey(pk: Hex, x: Hex, y: Hex, requireUV: boolean): Promise<Hex> {
  const {account, wallet} = walletOf(pk);
  const installed = await isModuleInstalled(account.address, 1, ADDR.webauthnValidator);

  if (!installed) {
    const initData = encodeAbiParameters(
      [{type: "bytes32"}, {type: "bytes32"}, {type: "bool"}],
      [x, y, requireUV],
    );
    return wallet.sendTransaction({
      to: account.address,
      data: encodeFunctionData({
        abi: accountAbi,
        functionName: "installModule",
        args: [1n, ADDR.webauthnValidator, initData],
      }),
    });
  }

  const setPassKeyData = encodeFunctionData({
    abi: webauthnAbi,
    functionName: "setPassKey",
    args: [x, y, requireUV],
  });
  const calls: Call[] = [{target: ADDR.webauthnValidator, value: 0n, data: setPassKeyData}];
  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({
      abi: accountAbi,
      functionName: "execute",
      args: [MODE_BATCH, encodeAbiParameters([callTupleArrayParam], [calls])],
    }),
  });
}

// ───────────────────────── passkey 交易签名 / passkey-signed execution ─────────────────────────

/** 计算签名路径的 execHash（即 passkey 的 challenge）/ compute the signed-path execHash (the passkey challenge). */
export async function buildExecHash(account: Address, calls: Call[]): Promise<Hex> {
  const nonce = await publicClient.readContract({
    address: account,
    abi: accountAbi,
    functionName: "getNonce",
  });
  return publicClient.readContract({
    address: account,
    abi: accountAbi,
    functionName: "hashExecute",
    args: [nonce, calls],
  });
}

/**
 * 用 passkey 断言授权一笔批量执行。
 * executionData = abi.encode(Call[], opData)；opData = abi.encode(webauthnValidator, sig)；
 * sig = abi.encode(WebAuthnAuth)。任意地址都可提交，这里由 burner EOA 自付 gas 提交。
 */
export async function sendPasskeyExecute(pk: Hex, calls: Call[], auth: EncodedWebAuthnAuth): Promise<Hex> {
  const {wallet, account} = walletOf(pk);

  const innerSig = encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          {name: "authenticatorData", type: "bytes"},
          {name: "clientDataJSON", type: "string"},
          {name: "challengeIndex", type: "uint256"},
          {name: "typeIndex", type: "uint256"},
          {name: "r", type: "bytes32"},
          {name: "s", type: "bytes32"},
        ],
      },
    ],
    [auth],
  );
  const opData = encodeAbiParameters([{type: "address"}, {type: "bytes"}], [ADDR.webauthnValidator, innerSig]);
  const executionData = encodeAbiParameters([callTupleArrayParam, {type: "bytes"}], [calls, opData]);

  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({
      abi: accountAbi,
      functionName: "execute",
      args: [MODE_BATCH_OPDATA, executionData],
    }),
  });
}

// ───────────────────────── session key（type-1 validator）/ session keys ─────────────────────────

/** session key 私钥按账户存浏览器本地（仅测试网）/ the session private key is kept per-account in localStorage. */
function sessionPkKey(account: Address) {
  return `my7702.session.${account.toLowerCase()}`;
}
export function loadSessionPk(account: Address): Hex | null {
  const v = localStorage.getItem(sessionPkKey(account));
  return v && /^0x[0-9a-fA-F]{64}$/.test(v) ? (v as Hex) : null;
}
export function saveSessionPk(account: Address, pk: Hex) {
  localStorage.setItem(sessionPkKey(account), pk);
}
export function clearSessionPk(account: Address) {
  localStorage.removeItem(sessionPkKey(account));
}

/** 读取某账户下某 session key 的策略（exists=false 表示未登记）/ read a session's policy (exists=false if none). */
export async function getSessionPolicy(account: Address, sessionKey: Address): Promise<SessionPolicy> {
  const p = await publicClient.readContract({
    address: ADDR.sessionValidator,
    abi: sessionAbi,
    functionName: "getSession",
    args: [account, sessionKey],
  });
  return p as SessionPolicy;
}

/**
 * 登记/更新一个 session 策略：账户(EOA)直接调用模块，模块以 msg.sender 为账户 key 落库。
 * 不需要走 execute——installSession 用 msg.sender 作账户归属，EOA 直发即 msg.sender==account。
 * Register/update a session: the EOA calls the module directly; it keys storage by msg.sender == account.
 */
export async function installSession(pk: Hex, sessionKey: Address, policy: SessionPolicy): Promise<Hex> {
  const {wallet} = walletOf(pk);
  return wallet.sendTransaction({
    to: ADDR.sessionValidator,
    data: encodeFunctionData({abi: sessionAbi, functionName: "installSession", args: [sessionKey, policy]}),
  });
}

/** 撤销一个 session（即时失效；在途签名因 exists==false 失败）/ revoke a session (immediate). */
export async function revokeSession(pk: Hex, sessionKey: Address): Promise<Hex> {
  const {wallet} = walletOf(pk);
  return wallet.sendTransaction({
    to: ADDR.sessionValidator,
    data: encodeFunctionData({abi: sessionAbi, functionName: "revokeSession", args: [sessionKey]}),
  });
}

/**
 * 用 session key 授权一笔批量执行：session key 只对 execHash 签名（secp256k1，强制 low-s），
 * 由 burner EOA 提交并自付 gas（任意地址都可提交）。校验/作用域全在链上 validateExecution 完成。
 * opData = abi.encode(sessionValidator, 65 字节 sig)；executionData = abi.encode(Call[], opData)。
 * A session key signs the execHash; the burner EOA submits & pays gas. Scoping is enforced on-chain.
 */
export async function sendSessionExecute(pk: Hex, sessionPk: Hex, calls: Call[]): Promise<Hex> {
  const {wallet, account} = walletOf(pk);
  const execHash = await buildExecHash(account.address, calls);
  const signature = await sign({hash: execHash, privateKey: sessionPk});
  const sig = serializeSignature(signature); // r||s||v，v=27/28，与 ECDSA.recover 期望一致
  const opData = encodeAbiParameters([{type: "address"}, {type: "bytes"}], [ADDR.sessionValidator, sig]);
  const executionData = encodeAbiParameters([callTupleArrayParam, {type: "bytes"}], [calls, opData]);
  return wallet.sendTransaction({
    to: account.address,
    data: encodeFunctionData({abi: accountAbi, functionName: "execute", args: [MODE_BATCH_OPDATA, executionData]}),
  });
}

// ───────────────────────── 支出上限 hook（type-4）/ spending-limit hook ─────────────────────────

/** 读取某账户当前的单笔 ETH 上限（wei）/ read an account's current per-tx ETH cap (wei). */
export async function getSpendLimit(account: Address): Promise<bigint> {
  return publicClient.readContract({
    address: ADDR.spendingHook,
    abi: spendingHookAbi,
    functionName: "maxValuePerTx",
    args: [account],
  });
}

/**
 * 更改单笔支出上限：账户(EOA)直接调用 hook 的 onInstall(abi.encode(cap))，以 msg.sender 为账户 key 覆盖上限。
 * 已安装的 hook 无需卸载重装；下一次 execute 的 preCheck 立即按新上限拦截。
 * Change the per-tx spend cap: the EOA calls onInstall(abi.encode(cap)) directly; it overwrites the cap keyed by
 * msg.sender. No uninstall/reinstall needed — the next execute's preCheck enforces the new cap immediately.
 */
export async function setSpendLimit(pk: Hex, capWei: bigint): Promise<Hex> {
  const {wallet} = walletOf(pk);
  const data = encodeAbiParameters([{type: "uint256"}], [capWei]);
  return wallet.sendTransaction({
    to: ADDR.spendingHook,
    data: encodeFunctionData({abi: spendingHookAbi, functionName: "onInstall", args: [data]}),
  });
}

export async function waitReceipt(hash: Hex) {
  return publicClient.waitForTransactionReceipt({hash});
}
