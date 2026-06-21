import {StrictMode} from "react";
import {createRoot} from "react-dom/client";
import {WagmiProvider} from "wagmi";
import {QueryClient, QueryClientProvider} from "@tanstack/react-query";
import {RainbowKitProvider, darkTheme, lightTheme} from "@rainbow-me/rainbowkit";
import {Toaster} from "sonner";
import "@rainbow-me/rainbowkit/styles.css";
import "./index.css";
import {wagmiConfig} from "@/lib/wagmi";
import {ThemeProvider, useTheme} from "@/lib/theme";
import App from "./App";

const queryClient = new QueryClient();

/** 让 RainbowKit 弹窗与 sonner 提示跟随白天/黑夜主题 / sync RainbowKit modal + toasts to the theme. */
function ThemedApp() {
  const {theme} = useTheme();
  return (
    <RainbowKitProvider theme={theme === "dark" ? darkTheme() : lightTheme()}>
      <App />
      <Toaster richColors position="top-right" closeButton theme={theme} />
    </RainbowKitProvider>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          <ThemedApp />
        </ThemeProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>,
);
