import {useEffect, useState} from "react";
import {formatEther, type Address} from "viem";
import {Copy, RefreshCw, Wallet} from "lucide-react";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {addrOf, PRESET_TEST_PK, publicClient} from "@/lib/account";
import {FAUCET_URL} from "@/lib/chain";
import {shortAddr} from "@/lib/utils";
import {toast} from "sonner";

interface Props {
  address: Address | null;
  importPreset: () => void;
  clear: () => void;
  refreshKey: number;
  bump: () => void;
}

export function BurnerAccount({address, importPreset, refreshKey, bump}: Props) {
  const [balance, setBalance] = useState<bigint | null>(null);
  const presetAddress = /^0x[0-9a-fA-F]{64}$/.test(PRESET_TEST_PK) ? addrOf(PRESET_TEST_PK) : null;

  useEffect(() => {
    importPreset();

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

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Wallet className="size-4" /> 7702 预设测试账户
        </CardTitle>
        <CardDescription className="[overflow-wrap:anywhere]">
          委托到自定义合约的 7702 授权签的是 <code className="text-[11px]">keccak256(0x05‖rlp[chainId,address,nonce])</code>
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!address ? (
          <div className="space-y-3">
            {presetAddress && (
              <Badge variant="secondary" className="font-mono">
                {shortAddr(presetAddress)}
              </Badge>
            )}
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
              <Button asChild variant="outline" size="sm">
                <a href={FAUCET_URL} target="_blank" rel="noreferrer">
                  领水龙头
                </a>
              </Button>
            </div>

            {balance === 0n && (
              <p className="text-sm text-destructive">余额为 0，先领水龙头，否则无法发交易。</p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
