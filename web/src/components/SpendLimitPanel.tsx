import {useEffect, useState} from "react";
import {formatEther, parseEther, type Address, type Hex} from "viem";
import {Gauge, Save} from "lucide-react";
import {toast} from "sonner";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {Input} from "@/components/ui/input";
import {Label} from "@/components/ui/label";
import {getSpendLimit, isModuleInstalled, setSpendLimit} from "@/lib/account";
import {ADDR} from "@/lib/contracts";
import {runTx} from "@/lib/tx";

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  refreshKey: number;
  bump: () => void;
}

export function SpendLimitPanel({pk, account, delegated, refreshKey, bump}: Props) {
  const [installed, setInstalled] = useState<boolean | null>(null);
  const [cap, setCap] = useState<bigint | null>(null);
  const [newCap, setNewCap] = useState("0.05");

  useEffect(() => {
    let alive = true;
    if (!account || !delegated) {
      setInstalled(null);
      setCap(null);
      return;
    }
    isModuleInstalled(account, 4, ADDR.spendingHook).then((v) => alive && setInstalled(v));
    getSpendLimit(account).then((v) => alive && setCap(v));
    return () => {
      alive = false;
    };
  }, [account, delegated, refreshKey]);

  async function update() {
    if (!pk) return;
    let capWei: bigint;
    try {
      capWei = parseEther((newCap || "0").trim());
    } catch {
      return toast.error("金额格式错误");
    }
    await runTx(`更新单笔上限为 ${newCap} ETH`, () => setSpendLimit(pk, capWei), bump);
  }

  const canUpdate = delegated && installed === true;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Gauge className="size-4" /> ⑤ 单笔支出上限 (SpendingLimitHook)
        </CardTitle>
        <CardDescription>
          type-4 hook 在每次 <code>execute</code> 前强制「单笔交易实际转出 ETH 总额 ≤ 上限」。这里更改该上限——账户
          重新调用 hook 的 <code>onInstall(cap)</code>（以 <code>msg.sender</code> 为账户 key 覆盖），无需卸载重装。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!delegated && <p className="text-sm text-muted-foreground">需先完成 7702 升级。</p>}
        {delegated && installed === false && (
          <p className="text-sm text-muted-foreground">需先在「② 插件商店」安装 SpendingLimitHook。</p>
        )}

        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">当前上限：</span>
          {cap === null ? (
            <span className="text-muted-foreground">{delegated ? "查询中…" : "—"}</span>
          ) : (
            <Badge variant={installed ? "success" : "outline"} className="font-mono">
              {formatEther(cap)} ETH
            </Badge>
          )}
          {installed === false && <span className="text-xs text-muted-foreground">（hook 未安装，上限不生效）</span>}
        </div>

        <div className="space-y-2 rounded-lg border p-3">
          <div className="space-y-1">
            <Label>新的单笔上限 (ETH)</Label>
            <Input value={newCap} onChange={(e) => setNewCap(e.target.value)} placeholder="0.05" />
          </div>
          <Button className="w-full" disabled={!pk || !canUpdate} onClick={update}>
            <Save /> 更新单笔上限
          </Button>
          <p className="text-xs text-muted-foreground">
            改完到「⑥ 批量执行」发一笔超过上限的转账 → hook 会以 <code>SpendingLimitExceeded</code> 拦截整笔。
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
