import {type Address, parseEther} from "viem";

const env = import.meta.env;

/** 已部署到 MegaETH(6343) 的地址（broadcast/Deploy.s.sol/6343）/ deployed addresses. */
/** 占位零地址：未配置某模块时用，配合 isDeployed 做兜底 / zero placeholder for an unset module address. */
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

/** 已部署到 MegaETH(6343) 的地址（broadcast/Deploy.s.sol/6343/run-latest.json，commit 129ec41）。 */
export const ADDR = {
  accountImpl: (env.VITE_ACCOUNT_IMPL ?? "0x056EB0b17d8640b6DD1582f82B12A44A408aB5b5") as Address,
  sessionValidator: (env.VITE_SESSION_VALIDATOR ?? "0x0351db74C742C25b230F70D562d6f3FF51B5Bfa0") as Address,
  webauthnValidator: (env.VITE_WEBAUTHN_VALIDATOR ?? "0x9267ab02DaaaC0069Eaf76efCD710469148C2888") as Address,
  spendingHook: (env.VITE_SPENDING_HOOK ?? "0xAB715C33eFF07eAef731a5b4E625359828e635F9") as Address,
  exampleExecutor: (env.VITE_EXAMPLE_EXECUTOR ?? "0xd066df02F5775C1b34b0CdC915fA37390115A141") as Address,
  multisigValidator: (env.VITE_MULTISIG_VALIDATOR ?? "0x722a36Ff20ec0feFb8A9558a4FbB63EB19430d54") as Address,
} as const;

/** 某模块地址是否已部署（非占位零地址）/ whether a module address is deployed (not the zero placeholder). */
export function isDeployed(addr: Address): boolean {
  return addr.toLowerCase() !== ZERO_ADDRESS.toLowerCase();
}

/** 默认 mint 代币：MegaETH 测试网 Mock USDM（symbol USDM，6 位小数，mint 公开免权限）。
 *  Default mint token: MegaETH testnet Mock USDM (6 decimals, permissionless mint). */
export const USDM_ADDRESS = "0x1BeFa17Db4c32dA66ec5A22e6462Fd8af839C788" as Address;

/** ERC-7821 模式常量（取自 Account.sol）/ ERC-7821 mode constants. */
export const MODE_BATCH = "0x0100000000000000000000000000000000000000000000000000000000000000" as const;
export const MODE_BATCH_OPDATA = "0x0100000000007821000100000000000000000000000000000000000000000000" as const;

/** Account.sol 子集 ABI / subset of the Account ABI used by the dapp. */
export const accountAbi = [
  {
    type: "function",
    name: "execute",
    stateMutability: "payable",
    inputs: [
      {name: "mode", type: "bytes32"},
      {name: "executionData", type: "bytes"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "installModule",
    stateMutability: "nonpayable",
    inputs: [
      {name: "typeId", type: "uint256"},
      {name: "module", type: "address"},
      {name: "initData", type: "bytes"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "uninstallModule",
    stateMutability: "nonpayable",
    inputs: [
      {name: "typeId", type: "uint256"},
      {name: "module", type: "address"},
      {name: "deInitData", type: "bytes"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "isModuleInstalled",
    stateMutability: "view",
    inputs: [
      {name: "typeId", type: "uint256"},
      {name: "module", type: "address"},
      {name: "ctx", type: "bytes"},
    ],
    outputs: [{type: "bool"}],
  },
  {
    type: "function",
    name: "getNonce",
    stateMutability: "view",
    inputs: [],
    outputs: [{type: "uint256"}],
  },
  {
    type: "function",
    name: "hashExecute",
    stateMutability: "view",
    inputs: [
      {name: "nonce", type: "uint256"},
      {
        name: "calls",
        type: "tuple[]",
        components: [
          {name: "target", type: "address"},
          {name: "value", type: "uint256"},
          {name: "data", type: "bytes"},
        ],
      },
    ],
    outputs: [{type: "bytes32"}],
  },
] as const;

/** WebAuthnValidator 子集 ABI / subset of the WebAuthn validator ABI. */
export const webauthnAbi = [
  {
    type: "function",
    name: "setPassKey",
    stateMutability: "nonpayable",
    inputs: [
      {name: "x", type: "bytes32"},
      {name: "y", type: "bytes32"},
      {name: "requireUV", type: "bool"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "passKeys",
    stateMutability: "view",
    inputs: [{name: "account", type: "address"}],
    outputs: [
      {name: "x", type: "bytes32"},
      {name: "y", type: "bytes32"},
      {name: "requireUV", type: "bool"},
      {name: "set", type: "bool"},
    ],
  },
] as const;

/** SessionKeyValidator 子集 ABI / subset of the session-key validator ABI. */
export const sessionAbi = [
  {
    type: "function",
    name: "installSession",
    stateMutability: "nonpayable",
    inputs: [
      {name: "sessionKey", type: "address"},
      {
        name: "p",
        type: "tuple",
        components: [
          {name: "validAfter", type: "uint48"},
          {name: "validUntil", type: "uint48"},
          {name: "perCallEthCap", type: "uint256"},
          {name: "targets", type: "address[]"},
          {name: "selectors", type: "bytes4[]"},
          {name: "exists", type: "bool"},
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "revokeSession",
    stateMutability: "nonpayable",
    inputs: [{name: "sessionKey", type: "address"}],
    outputs: [],
  },
  {
    type: "function",
    name: "getSession",
    stateMutability: "view",
    inputs: [
      {name: "account", type: "address"},
      {name: "sessionKey", type: "address"},
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          {name: "validAfter", type: "uint48"},
          {name: "validUntil", type: "uint48"},
          {name: "perCallEthCap", type: "uint256"},
          {name: "targets", type: "address[]"},
          {name: "selectors", type: "bytes4[]"},
          {name: "exists", type: "bool"},
        ],
      },
    ],
  },
] as const;

/** SpendingLimitHook 子集 ABI / subset of the spending-limit hook ABI. */
export const spendingHookAbi = [
  {
    type: "function",
    name: "maxValuePerTx",
    stateMutability: "view",
    inputs: [{name: "account", type: "address"}],
    outputs: [{type: "uint256"}],
  },
  {
    // 部署版只用 onInstall 设置上限（以 msg.sender 为账户 key）；账户重新调用即可更新。
    // The deployed hook's only cap setter is onInstall (keyed by msg.sender); the account re-calls it to update.
    type: "function",
    name: "onInstall",
    stateMutability: "nonpayable",
    inputs: [{name: "data", type: "bytes"}],
    outputs: [],
  },
] as const;

/** MultisigValidator 子集 ABI / subset of the multisig validator ABI. */
export const multisigAbi = [
  {
    // 设置/更新多签配置（账户直调，msg.sender==account）/ set/update config, account-only.
    type: "function",
    name: "setConfig",
    stateMutability: "nonpayable",
    inputs: [
      {name: "signers", type: "address[]"},
      {name: "threshold", type: "uint256"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "getConfig",
    stateMutability: "view",
    inputs: [{name: "account", type: "address"}],
    outputs: [
      {name: "signers", type: "address[]"},
      {name: "threshold", type: "uint256"},
      {name: "exists", type: "bool"},
    ],
  },
] as const;

/** 最小 ERC20 ABI（mint + decimals + balanceOf），用于「批量执行」里的 mint 代币示例。
 *  Minimal ERC20 ABI for the batch-execution mint demo. */
export const erc20Abi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      {name: "to", type: "address"},
      {name: "amount", type: "uint256"},
    ],
    outputs: [],
  },
  {type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{type: "uint8"}]},
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{name: "account", type: "address"}],
    outputs: [{type: "uint256"}],
  },
] as const;

/** ERC-7821 Call 元组的 ABI 参数描述（用于 encodeAbiParameters）/ ABI param for a Call[] tuple. */
export const callTupleArrayParam = {
  type: "tuple[]",
  components: [
    {name: "target", type: "address"},
    {name: "value", type: "uint256"},
    {name: "data", type: "bytes"},
  ],
} as const;

export type ModuleType = 1 | 2 | 4;

/** 插件商店里展示的模块目录 / the module catalog shown in the plugin store. */
export interface PluginMeta {
  key: string;
  name: string;
  typeId: ModuleType;
  typeLabel: string;
  address: Address;
  desc: string;
  /** 安装时的 initData 编码方式 / how to build initData on install. */
  initData: (account: Address) => `0x${string}`;
}

import {encodeAbiParameters} from "viem";

export const PLUGINS: PluginMeta[] = [
  {
    key: "session",
    name: "SessionKeyValidator",
    typeId: 1,
    typeLabel: "validator",
    address: ADDR.sessionValidator,
    desc: "带作用域的临时密钥：时间窗 + 目标/选择器白名单 + 单笔 ETH 上限。",
    initData: () => "0x",
  },
  {
    key: "webauthn",
    name: "WebAuthnValidator",
    typeId: 1,
    typeLabel: "validator",
    address: ADDR.webauthnValidator,
    desc: "Passkey(P256/WebAuthn) 验证器。安装后到「Passkey」面板注册公钥。",
    initData: () => "0x",
  },
  {
    key: "multisig",
    name: "MultisigValidator",
    typeId: 1,
    typeLabel: "validator",
    address: ADDR.multisigValidator,
    desc: "M-of-N 多签验证器：一笔执行需 ≥M 个登记签名者各签一份。安装后到「多签」面板配置签名者与阈值。",
    initData: () => "0x", // 空安装；签名者/阈值在面板里 setConfig / install empty, configure in the panel
  },
  {
    key: "hook",
    name: "SpendingLimitHook",
    typeId: 4,
    typeLabel: "hook",
    address: ADDR.spendingHook,
    desc: "示例钩子：每笔交易实际转出 ETH 总额上限（默认 0.01 ETH）。",
    initData: () => encodeAbiParameters([{type: "uint256"}], [parseEther("0.01")]),
  },
  {
    key: "executor",
    name: "ExampleExecutor",
    typeId: 2,
    typeLabel: "executor",
    address: ADDR.exampleExecutor,
    desc: "示例执行器：被授权 operator 代账户批量执行（operator 默认设为本账户）。",
    initData: (account) => encodeAbiParameters([{type: "address"}], [account]),
  },
];
