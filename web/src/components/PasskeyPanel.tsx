import {useEffect, useState} from "react";
import {isAddress, parseEther, type Address, type Hex} from "viem";
import {Fingerprint, PenLine} from "lucide-react";
import {toast} from "sonner";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {Input} from "@/components/ui/input";
import {Label} from "@/components/ui/label";
import {buildExecHash, getPassKeySet, registerPassKey, sendPasskeyExecute, type Call} from "@/lib/account";
import {createPasskey, loadPasskey, signPasskey} from "@/lib/passkey";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";

const DEMO_RECIPIENT = "0x000000000000000000000000000000000000dEaD";

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  refreshKey: number;
  bump: () => void;
}

export function PasskeyPanel({pk, account, delegated, refreshKey, bump}: Props) {
  const [onChainSet, setOnChainSet] = useState<boolean | null>(null);
  const [hasLocal, setHasLocal] = useState(false);
  const [recipient, setRecipient] = useState(DEMO_RECIPIENT);
  const [amount, setAmount] = useState("0");

  useEffect(() => {
    let alive = true;
    if (!account || !delegated) {
      setOnChainSet(null);
      setHasLocal(false);
      return;
    }
    setHasLocal(!!loadPasskey(account));
    getPassKeySet(account).then((v) => alive && setOnChainSet(v));
    return () => {
      alive = false;
    };
  }, [account, delegated, refreshKey]);

  async function register() {
    if (!pk || !account) return;
    await runTx(
      "注册 passkey",
      async () => {
        const {x, y} = await createPasskey(account, `my-7702 · ${shortAddr(account)}`);
        return registerPassKey(pk, x, y, false);
      },
      bump,
    );
  }

  async function signTx() {
    if (!pk || !account) return;
    const cred = loadPasskey(account);
    if (!cred) return toast.error("本机没有该账户的 passkey，请先在本设备注册");
    if (!isAddress(recipient)) return toast.error("收款地址格式错误");
    let value: bigint;
    try {
      value = parseEther((amount || "0").trim());
    } catch {
      return toast.error("金额格式错误");
    }
    const calls: Call[] = [{target: recipient as Address, value, data: "0x"}];
    await runTx(
      "passkey 授权交易",
      async () => {
        const challenge = await buildExecHash(account, calls); // = execHash，作为 WebAuthn challenge
        const auth = await signPasskey(challenge, cred.id); // 弹出 Touch ID / Windows Hello
        return sendPasskeyExecute(pk, calls, auth);
      },
      bump,
    );
  }

  const canSign = delegated && hasLocal && onChainSet === true;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Fingerprint className="size-4" /> ④ Passkey 交易签名
        </CardTitle>
        <CardDescription>
          用真实设备 passkey（Touch ID / Windows Hello / 安全密钥）的 P256/WebAuthn 断言授权一笔批量执行，
          challenge 即账户算出的 execHash（绑定 chainId+account+nonce）。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">状态：</span>
          {onChainSet === true ? (
            <Badge variant="success">公钥已注册</Badge>
          ) : (
            <Badge variant="outline">未注册</Badge>
          )}
          {hasLocal ? (
            <Badge variant="secondary">本机有凭证</Badge>
          ) : (
            <Badge variant="outline">本机无凭证</Badge>
          )}
        </div>

        <Button disabled={!pk || !delegated} onClick={register}>
          <Fingerprint /> {onChainSet ? "重新注册 / 轮换 passkey" : "注册 passkey"}
        </Button>

        <div className="space-y-2 rounded-lg border p-3">
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_120px]">
            <div className="space-y-1">
              <Label>收款地址</Label>
              <Input value={recipient} onChange={(e) => setRecipient(e.target.value)} className="font-mono text-xs" />
            </div>
            <div className="space-y-1">
              <Label>金额 (ETH)</Label>
              <Input value={amount} onChange={(e) => setAmount(e.target.value)} />
            </div>
          </div>
          <Button variant="secondary" className="w-full" disabled={!pk || !canSign} onClick={signTx}>
            <PenLine /> 用 passkey 签名并提交
          </Button>
          {!delegated && <p className="text-xs text-muted-foreground">需先完成 7702 升级。</p>}
          {delegated && !canSign && (
            <p className="text-xs text-muted-foreground">先注册 passkey（会自动安装 WebAuthnValidator）。</p>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
