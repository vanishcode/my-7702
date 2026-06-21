import React from "react";
import {toast} from "sonner";
import type {Hex} from "viem";
import {waitReceipt} from "./account";
import {megaethTestnet} from "./chain";

export function explorerTx(hash: Hex) {
  return `${megaethTestnet.blockExplorers.default.url}/tx/${hash}`;
}

function shortErr(e: unknown): string {
  const anyE = e as {shortMessage?: string; message?: string};
  return (anyE?.shortMessage || anyE?.message || String(e)).split("\n")[0].slice(0, 180);
}

/** 发交易 + 等回执 + toast 提示；成功后回调 onDone（用于刷新状态）。 */
export async function runTx(label: string, send: () => Promise<Hex>, onDone?: () => void): Promise<void> {
  const id = toast.loading(`${label}：提交中…`);
  try {
    const hash = await send();
    const rcpt = await waitReceipt(hash);
    if (rcpt.status !== "success") throw new Error("交易回滚 / reverted");
    onDone?.();
    toast.success(`${label} 成功`, {id, description: React.createElement("a", {href: explorerTx(hash), target: "_blank"}, explorerTx(hash))});
  } catch (e) {
    toast.error(`${label} 失败：${shortErr(e)}`, {id});
  }
}
