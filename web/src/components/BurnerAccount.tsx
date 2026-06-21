import {useEffect, useState} from "react";
import {formatEther, parseEther, type Address} from "viem";
import {useAccount, useSendTransaction} from "wagmi";
import {Copy, KeyRound, RefreshCw, Trash2, Wallet} from "lucide-react";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Input} from "@/components/ui/input";
import {Badge} from "@/components/ui/badge";
import {publicClient} from "@/lib/account";
import {FAUCET_URL} from "@/lib/chain";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";
import {toast} from "sonner";

interface Props {
  address: Address | null;
  generate: () => void;
  importPk: (v: string) => void;
  clear: () => void;
  refreshKey: number;
  bump: () => void;
}

export function BurnerAccount({address, generate, importPk, clear, refreshKey, bump}: Props) {
  const [balance, setBalance] = useState<bigint | null>(null);
  const [importVal, setImportVal] = useState("");
  const {address: connected} = useAccount();
  const {sendTransactionAsync} = useSendTransaction();

  useEffect(() => {
    let alive = true;
    if (!address) {
      setBalance(null);
      return;
    }
    publicClient.getBalance({address}).then((b) => alive && setBalance(b));
    return () => {
      alive = false;
    };
  }, [address, refreshKey]);

  async function fund() {
    if (!connected || !address) return;
    await runTx(
      "充值 0.01 ETH 到测试账户",
      () => sendTransactionAsync({to: address, value: parseEther("0.01")}),
      bump,
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Wallet className="size-4" /> 7702 测试账户（本地 burner 私钥）
        </CardTitle>
        <CardDescription className="[overflow-wrap:anywhere]">
          委托到自定义合约的 7702 授权签的是 <code className="text-[11px]">keccak256(0x05‖rlp[chainId,address,nonce])</code>
          ，注入钱包无法产出 → 用本地私钥由 viem 直接签。私钥仅存在浏览器 localStorage，请只用测试网。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!address ? (
          <div className="space-y-3">
            <Button onClick={generate} className="w-full">
              <KeyRound /> 生成新测试账户
            </Button>
            <div className="flex gap-2">
              <Input
                placeholder="或导入私钥 0x..."
                value={importVal}
                onChange={(e) => setImportVal(e.target.value)}
              />
              <Button
                variant="secondary"
                onClick={() => {
                  try {
                    importPk(importVal);
                    setImportVal("");
                  } catch (e) {
                    toast.error((e as Error).message);
                  }
                }}
              >
                导入
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="secondary" className="font-mono">
                {shortAddr(address)}
              </Badge>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  navigator.clipboard.writeText(address);
                  toast.success("地址已复制");
                }}
              >
                <Copy />
              </Button>
              <Button variant="ghost" size="icon" onClick={bump} title="刷新余额">
                <RefreshCw />
              </Button>
              <span className="text-sm text-muted-foreground">
                余额 {balance == null ? "…" : Number(formatEther(balance)).toFixed(5)} ETH
              </span>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button asChild variant="outline" size="sm">
                <a href={FAUCET_URL} target="_blank" rel="noreferrer">
                  领水龙头
                </a>
              </Button>
              <Button variant="outline" size="sm" onClick={fund} disabled={!connected}>
                {connected ? "用连接的钱包充值 0.01 ETH" : "（连接钱包后可充值）"}
              </Button>
              <Button variant="ghost" size="sm" onClick={clear}>
                <Trash2 /> 清除
              </Button>
            </div>

            {balance === 0n && (
              <p className="text-sm text-destructive">余额为 0，先领水龙头或用连接的钱包充值，否则无法发交易。</p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
