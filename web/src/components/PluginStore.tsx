import {useEffect, useState} from "react";
import {type Address, type Hex} from "viem";
import {Blocks, CheckCircle2} from "lucide-react";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {installModule, isModuleInstalled, uninstallModule} from "@/lib/account";
import {PLUGINS} from "@/lib/contracts";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  refreshKey: number;
  bump: () => void;
}

export function PluginStore({pk, account, delegated, refreshKey, bump}: Props) {
  const [installed, setInstalled] = useState<Record<string, boolean>>({});

  useEffect(() => {
    let alive = true;
    if (!account || !delegated) {
      setInstalled({});
      return;
    }
    Promise.all(
      PLUGINS.map((p) => isModuleInstalled(account, p.typeId, p.address).then((v) => [p.key, v] as const)),
    ).then((entries) => alive && setInstalled(Object.fromEntries(entries)));
    return () => {
      alive = false;
    };
  }, [account, delegated, refreshKey]);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Blocks className="size-4" /> ② 插件商店（ERC-7579 子集）
        </CardTitle>
        <CardDescription>
          validator(1) / executor(2) / hook(4) 三类模块自助装卸。安装走 ROOT 路径（账户给自己发交易调
          <code> installModule</code>）。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {!delegated && <p className="text-sm text-muted-foreground">需先完成 7702 升级，才能装卸插件。</p>}
        {PLUGINS.map((p) => {
          const on = installed[p.key];
          return (
            <div key={p.key} className="flex items-start justify-between gap-3 rounded-lg border p-3">
              <div className="min-w-0 space-y-1">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{p.name}</span>
                  <Badge variant="outline" className="text-[10px]">
                    type {p.typeId} · {p.typeLabel}
                  </Badge>
                  {on && (
                    <Badge variant="success" className="text-[10px]">
                      <CheckCircle2 className="mr-1 size-3" /> 已安装
                    </Badge>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">{p.desc}</p>
                <p className="font-mono text-[10px] text-muted-foreground">{shortAddr(p.address, 10, 8)}</p>
              </div>
              <div className="shrink-0">
                {on ? (
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={!pk || !delegated}
                    onClick={() => pk && runTx(`卸载 ${p.name}`, () => uninstallModule(pk, p.typeId, p.address), bump)}
                  >
                    卸载
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    disabled={!pk || !delegated}
                    onClick={() =>
                      pk &&
                      account &&
                      runTx(`安装 ${p.name}`, () => installModule(pk, p.typeId, p.address, p.initData(account)), bump)
                    }
                  >
                    安装
                  </Button>
                )}
              </div>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
