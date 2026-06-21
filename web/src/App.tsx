import {useCallback, useEffect, useState} from "react";
import type {Address} from "viem";
import {ConnectButton} from "@rainbow-me/rainbowkit";
import {ThemeToggle} from "@/components/ThemeToggle";
import {useBurner} from "@/lib/useBurner";
import {getDelegation} from "@/lib/account";
import {ADDR} from "@/lib/contracts";
import {shortAddr} from "@/lib/utils";
import {BurnerAccount} from "@/components/BurnerAccount";
import {UpgradePanel} from "@/components/UpgradePanel";
import {PasskeyPanel} from "@/components/PasskeyPanel";
import {PluginStore} from "@/components/PluginStore";
import {BatchPanel} from "@/components/BatchPanel";
import {SessionPanel} from "@/components/SessionPanel";
import {SpendLimitPanel} from "@/components/SpendLimitPanel";

export default function App() {
  const {pk, address, generate, importPk, clear} = useBurner();
  const [refreshKey, setRefreshKey] = useState(0);
  const bump = useCallback(() => setRefreshKey((k) => k + 1), []);
  const [target, setTarget] = useState<Address | null | "loading">("loading");

  useEffect(() => {
    let alive = true;
    if (!address) {
      setTarget(null);
      return;
    }
    setTarget("loading");
    getDelegation(address).then((t) => alive && setTarget(t));
    return () => {
      alive = false;
    };
  }, [address, refreshKey]);

  const delegated = target !== "loading" && !!target && target.toLowerCase() === ADDR.accountImpl.toLowerCase();

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">my-7702 · 测试 dapp</h1>
          <p className="text-sm text-muted-foreground">最小化 EIP-7702 智能账户 · MegaETH 测试网 (6343)</p>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <ConnectButton showBalance={false} chainStatus="icon" />
        </div>
      </header>

      <BurnerAccount
        address={address}
        generate={generate}
        importPk={importPk}
        clear={clear}
        refreshKey={refreshKey}
        bump={bump}
      />

      <UpgradePanel pk={pk} target={target} bump={bump} />

      <PluginStore pk={pk} account={address} delegated={delegated} refreshKey={refreshKey} bump={bump} />

      <SessionPanel pk={pk} account={address} delegated={delegated} refreshKey={refreshKey} bump={bump} />

      <PasskeyPanel pk={pk} account={address} delegated={delegated} refreshKey={refreshKey} bump={bump} />

      <SpendLimitPanel pk={pk} account={address} delegated={delegated} refreshKey={refreshKey} bump={bump} />

      <BatchPanel pk={pk} account={address} delegated={delegated} bump={bump} />

      <footer className="pt-2 text-center text-xs text-muted-foreground">
        Account 实现 <span className="font-mono">{shortAddr(ADDR.accountImpl, 10, 8)}</span> · 仅测试网，私钥仅存浏览器本地
      </footer>
    </div>
  );
}
