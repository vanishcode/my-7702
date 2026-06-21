import {clsx, type ClassValue} from "clsx";
import {twMerge} from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** 缩短地址显示 / shorten an address for display. */
export function shortAddr(addr?: string, head = 6, tail = 4): string {
  if (!addr) return "";
  return `${addr.slice(0, head)}…${addr.slice(-tail)}`;
}
