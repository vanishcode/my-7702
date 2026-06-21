import {createContext, useCallback, useContext, useEffect, useMemo, useState} from "react";
import type {ReactNode} from "react";

/** 白天 / 黑夜 两种主题 / the two themes. */
export type Theme = "light" | "dark";

const STORAGE_KEY = "theme";

interface ThemeContextValue {
  theme: Theme;
  setTheme: (t: Theme) => void;
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

/**
 * 初始主题以 <html> 上的 class 为准：index.html 内联脚本已在 React 挂载前
 * 依据 localStorage → 系统偏好 设置好 `dark` 类，这里只是镜像它，避免闪烁。
 * The inline script in index.html is the source of truth; we mirror the DOM to avoid FOUC.
 */
function getInitialTheme(): Theme {
  if (typeof document !== "undefined") {
    return document.documentElement.classList.contains("dark") ? "dark" : "light";
  }
  return "dark";
}

function persist(t: Theme): void {
  try {
    localStorage.setItem(STORAGE_KEY, t);
  } catch {
    // 隐私模式等可能禁用 localStorage / storage may be unavailable (private mode)
  }
}

export function ThemeProvider({children}: {children: ReactNode}) {
  const [theme, setThemeState] = useState<Theme>(getInitialTheme);

  // 同步 <html> 的 dark 类（Tailwind v4 dark variant 依赖它）/ keep the dark class in sync
  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
  }, [theme]);

  // 用户未显式选择前，跟随系统切换 / follow the OS until the user makes an explicit choice
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = (e: MediaQueryListEvent) => {
      let stored: string | null = null;
      try {
        stored = localStorage.getItem(STORAGE_KEY);
      } catch {
        stored = null;
      }
      if (stored !== "light" && stored !== "dark") setThemeState(e.matches ? "dark" : "light");
    };
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  const setTheme = useCallback((t: Theme) => {
    persist(t);
    setThemeState(t);
  }, []);

  const toggle = useCallback(() => {
    setThemeState((prev) => {
      const next = prev === "dark" ? "light" : "dark";
      persist(next);
      return next;
    });
  }, []);

  const value = useMemo<ThemeContextValue>(() => ({theme, setTheme, toggle}), [theme, setTheme, toggle]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

/** 读取当前主题与切换器 / read the current theme and switchers. */
export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme 必须在 <ThemeProvider> 内使用 / must be used within <ThemeProvider>");
  return ctx;
}
