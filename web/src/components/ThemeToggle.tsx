import {Moon, Sun} from "lucide-react";
import {Button} from "@/components/ui/button";
import {useTheme} from "@/lib/theme";

/** 白天/黑夜切换按钮 / day/night toggle button. */
export function ThemeToggle() {
  const {theme, toggle} = useTheme();
  const isDark = theme === "dark";
  const label = isDark ? "切换到白天模式 / switch to light mode" : "切换到黑夜模式 / switch to dark mode";
  return (
    <Button variant="ghost" size="icon" onClick={toggle} title={label} aria-label={label}>
      {isDark ? <Sun /> : <Moon />}
    </Button>
  );
}
