import {StrictMode} from "react";
import {createRoot} from "react-dom/client";
import {Toaster} from "sonner";
import "./index.css";
import {ThemeProvider, useTheme} from "@/lib/theme";
import App from "./App";

/** 让 sonner 提示跟随白天/黑夜主题 / sync toasts to the theme. */
function ThemedApp() {
  const {theme} = useTheme();
  return (
    <>
      <App />
      <Toaster richColors position="top-right" closeButton theme={theme} />
    </>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <ThemedApp />
    </ThemeProvider>
  </StrictMode>,
);
