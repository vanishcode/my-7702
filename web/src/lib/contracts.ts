import {type Address, parseEther} from "viem";

const env = import.meta.env;

/** 已部署到 MegaETH(6343) 的地址（broadcast/Deploy.s.sol/6343）/ deployed addresses. */
export const ADDR = {
  accountImpl: (env.VITE_ACCOUNT_IMPL ?? "0xd631F7D616DA826E5D36d5Fe4F5Ba62cC5b7B277") as Address,
  sessionValidator: (env.VITE_SESSION_VALIDATOR ?? "0x54A776eF761591B3C4AdB455f3367450c95a1bEB") as Address,
  webauthnValidator: (env.VITE_WEBAUTHN_VALIDATOR ?? "0xd220a5e17aDe9e729f6D40470a13803100D6fAC1") as Address,
  spendingHook: (env.VITE_SPENDING_HOOK ?? "0xb5D566DF4B3ff76E3e3C93872FFe96Ae81a09c00") as Address,
  exampleExecutor: (env.VITE_EXAMPLE_EXECUTOR ?? "0xFe0caA7B3B9eBc9370E81e22DA0502075F954FD2") as Address,
} as const;

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
