import {useCallback, useState} from "react";
import type {Address, Hex} from "viem";
import {addrOf, clearPk, loadPk, PRESET_TEST_PK, savePk} from "./account";

/** 管理本地 burner 私钥（7702 测试账户）/ manage the local burner key (the 7702 test account). */
export function useBurner() {
  const [pk, setPk] = useState<Hex | null>(() => loadPk());
  const address: Address | null = pk ? addrOf(pk) : null;

  const importPreset = useCallback(() => {
    const v = PRESET_TEST_PK.trim();
    if (!/^0x[0-9a-fA-F]{64}$/.test(v)) {
      throw new Error("预设私钥格式错误：需 0x + 64 位十六进制 / expected 0x + 64 hex chars");
    }
    savePk(v as Hex);
    setPk(v as Hex);
  }, []);

  const clear = useCallback(() => {
    clearPk();
    setPk(null);
  }, []);

  return {pk, address, importPreset, clear};
}
