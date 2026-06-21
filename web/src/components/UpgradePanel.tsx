import {type Address, type Hex} from "viem";
import {ArrowUpCircle, CheckCircle2, CircleSlash} from "lucide-react";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {delegate, undelegate} from "@/lib/account";
import {ADDR} from "@/lib/contracts";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";

interface Props {
  pk: Hex | null;
  /** 当前委托目标：Address=已委托，null=未委托，"loading"=查询中。 */
  target: Address | null | "loading";
  bump: () => void;
}

export function UpgradePanel({pk, target, bump}: Props) {
  const isOurs = target && target !== "loading" && target.toLowerCase() === ADDR.accountImpl.toLowerCase();

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ArrowUpCircle className="size-4" /> ① 7702 升级
        </CardTitle>
        <CardDescription>
          发一笔 type-4 交易，把 EOA 的 code 委托到 Account 实现单例（<code>{shortAddr(ADDR.accountImpl)}</code>）。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center gap-2 text-sm">
          <span className="text-muted-foreground">委托状态：</span>
          {target === "loading" ? (
            <span className="text-muted-foreground">查询中…</span>
          ) : isOurs ? (
            <Badge variant="success">
              <CheckCircle2 className="mr-1 size-3" /> 已升级
            </Badge>
          ) : target ? (
            <Badge variant="outline" className="font-mono">
              委托到其他合约 {shortAddr(target)}
            </Badge>
          ) : (
            <Badge variant="outline">
              <CircleSlash className="mr-1 size-3" /> 未委托（普通 EOA）
            </Badge>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <Button disabled={!pk || !!isOurs} onClick={() => pk && runTx("7702 升级", () => delegate(pk), bump)}>
            <ArrowUpCircle /> 升级到 Account
          </Button>
          <Button
            variant="outline"
            disabled={!pk || !target || target === "loading"}
            onClick={() => pk && runTx("撤销委托", () => undelegate(pk), bump)}
          >
            撤销委托
          </Button>
        </div>
        {!pk && <p className="text-sm text-muted-foreground">先在上方创建/导入测试账户。</p>}
      </CardContent>
    </Card>
  );
}
