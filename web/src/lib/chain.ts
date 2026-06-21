import {defineChain} from "viem";

/**
 * MegaETH 测试网 / MegaETH testnet.
 * 链 id 固定 6343（旧链 6342 已废弃，勿用）。viem 自带的可能是废弃链，这里手动定义。
 * Chain id pinned to 6343 (the old 6342 is deprecated). Defined manually to avoid the stale built-in.
 */
export const megaethTestnet = defineChain({
  id: 6343,
  name: "MegaETH Testnet",
  nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
  rpcUrls: {
    default: {http: ["https://carrot.megaeth.com/rpc"]},
  },
  blockExplorers: {
    default: {name: "Etherscan", url: "https://testnet-mega.etherscan.io"},
  },
  testnet: true,
});

export const FAUCET_URL = "https://testnet.megaeth.com";
