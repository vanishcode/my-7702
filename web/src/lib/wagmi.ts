import {getDefaultConfig} from "@rainbow-me/rainbowkit";
import {http} from "wagmi";
import {megaethTestnet} from "./chain";

/**
 * wagmi + RainbowKit 配置。注入钱包（MetaMask 等）无需 WalletConnect projectId；
 * 仅当用 WalletConnect 扫码弹窗时才需要真实 id（见 .env.example）。
 * Injected wallets need no projectId; only the WalletConnect modal does.
 */
export const wagmiConfig = getDefaultConfig({
  appName: "my-7702",
  projectId: import.meta.env.VITE_WC_PROJECT_ID || "0000000000000000000000000000000000",
  chains: [megaethTestnet],
  transports: {
    [megaethTestnet.id]: http(),
  },
  ssr: false,
});
