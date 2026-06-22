import {useEffect, useState} from "react";
import {formatEther, isAddress, parseEther, type Address, type Hex} from "viem";
import {KeyRound, RefreshCw, Send, ShieldCheck, Trash2} from "lucide-react";
import {toast} from "sonner";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {Input} from "@/components/ui/input";
import {Label} from "@/components/ui/label";
import {
  addrOf,
  getSessionPolicy,
  installSession,
  isModuleInstalled,
  loadSessionPk,
  newPk,
  revokeSession,
  saveSessionPk,
  sendSessionExecute,
  type Call,
  type SessionPolicy,
} from "@/lib/account";
import {ADDR} from "@/lib/contracts";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";

const DEMO_TARGET = "0x6ab1d676904b232fa27e0cd9a1592759c5954eff";

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  refreshKey: number;
  bump: () => void;
}

export function SessionPanel({pk, account, delegated, refreshKey, bump}: Props) {
  const [sessionAddr, setSessionAddr] = useState<Address | null>(null);
  const [moduleInstalled, setModuleInstalled] = useState<boolean | null>(null);
  const [policy, setPolicy] = useState<SessionPolicy | null>(null);

  // 策略表单 / policy form
  const [target, setTarget] = useState(DEMO_TARGET);
  const [cap, setCap] = useState("0.001");
  const [ttl, setTtl] = useState("60"); // 分钟，0 = 永不过期 / minutes, 0 = never

  // 使用表单 / use form
  const [sendTo, setSendTo] = useState(DEMO_TARGET);
  const [sendAmt, setSendAmt] = useState("0.0005");

  useEffect(() => {
    let alive = true;
    if (!account) {
      setSessionAddr(null);
      setModuleInstalled(null);
      setPolicy(null);
      return;
    }
    // session key 是本地的，未升级也可先生成查看 / the key is local, show it even before delegation.
    const spk = loadSessionPk(account);
    const addr = spk ? addrOf(spk) : null;
    setSessionAddr(addr);
    if (!delegated) {
      setModuleInstalled(null);
      setPolicy(null);
      return;
    }
    // 链上读取仅在已升级后进行 / on-chain reads only once delegated.
    isModuleInstalled(account, 1, ADDR.sessionValidator).then((v) => alive && setModuleInstalled(v));
    if (addr) {
      getSessionPolicy(account, addr).then((p) => alive && setPolicy(p.exists ? p : null));
    } else {
      setPolicy(null);
    }
    return () => {
      alive = false;
    };
  }, [account, delegated, refreshKey]);

  function genKey() {
    if (!account) return;
    saveSessionPk(account, newPk());
    bump();
    toast.success("已生成新的 session key（仅存浏览器本地）");
  }

  async function register() {
    if (!pk || !sessionAddr) return;
    if (!isAddress(target)) return toast.error("允许目标地址格式错误");
    let capWei: bigint;
    try {
      capWei = parseEther((cap || "0").trim());
    } catch {
      return toast.error("单笔上限金额格式错误");
    }
    const mins = Math.floor(Number(ttl || "0"));
    if (!Number.isFinite(mins) || mins < 0) return toast.error("有效期（分钟）格式错误");
    const validUntil = mins > 0 ? Math.floor(Date.now() / 1000) + mins * 60 : 0;
    const p: SessionPolicy = {
      validAfter: 0,
      validUntil,
      perCallEthCap: capWei,
      targets: [target as Address],
      selectors: [], // 空 = 通配，放行纯 ETH 转账（无选择器）/ wildcard, allows plain ETH transfers
      exists: true,
    };
    await runTx("登记 session 策略", () => installSession(pk, sessionAddr, p), bump);
  }

  async function revoke() {
    if (!pk || !sessionAddr) return;
    await runTx("撤销 session", () => revokeSession(pk, sessionAddr), bump);
  }

  async function send() {
    if (!pk || !account) return;
    const spk = loadSessionPk(account);
    if (!spk) return toast.error("本机没有该账户的 session key，请先生成并登记");
    if (!isAddress(sendTo)) return toast.error("收款地址格式错误");
    let value: bigint;
    try {
      value = parseEther((sendAmt || "0").trim());
    } catch {
      return toast.error("金额格式错误");
    }
    const calls: Call[] = [{target: sendTo as Address, value, data: "0x"}];
    await runTx("session key 授权交易", () => sendSessionExecute(pk, spk, calls), bump);
  }

  const canConfig = delegated && moduleInstalled === true;
  const canRegister = canConfig && !!sessionAddr;
  const canSend = canConfig && !!policy?.exists;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRound className="size-4" /> ③ Session Key 临时密钥
        </CardTitle>
        <CardDescription>
          登记一个带作用域的临时密钥（type-1 validator）：目标白名单 + 单笔 ETH 上限 + 有效期。该密钥只能在作用域内
          授权交易，且永远无法触达账户自身(admin)。签名者是 session key、提交者是 burner EOA（自付 gas，任意地址可提交）。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!delegated && <p className="text-sm text-muted-foreground">需先完成 7702 升级。</p>}
        {delegated && moduleInstalled === false && (
          <p className="text-sm text-muted-foreground">需先在「② 插件商店」安装 SessionKeyValidator。</p>
        )}

        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">session key：</span>
          {sessionAddr ? (
            <Badge variant="secondary" className="font-mono">
              {shortAddr(sessionAddr)}
            </Badge>
          ) : (
            <Badge variant="outline">未生成</Badge>
          )}
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            disabled={!account}
            onClick={genKey}
            title="生成 / 轮换 session key"
          >
            <RefreshCw />
          </Button>
          {policy?.exists ? <Badge variant="success">已登记策略</Badge> : <Badge variant="outline">未登记策略</Badge>}
        </div>

        {policy?.exists && (
          <div className="space-y-0.5 rounded-lg border border-dashed p-2 text-xs text-muted-foreground">
            <div>
              目标白名单：
              <span className="font-mono">
                {policy.targets.length ? policy.targets.map((t) => shortAddr(t)).join(", ") : "（空=拒绝一切）"}
              </span>
            </div>
            <div>单笔上限：{formatEther(policy.perCallEthCap)} ETH</div>
            <div>
              有效期：
              {policy.validUntil === 0 ? "永不过期" : new Date(policy.validUntil * 1000).toLocaleString()}
            </div>
          </div>
        )}

        <div className="space-y-2 rounded-lg border p-3">
          <p className="text-xs font-medium text-muted-foreground">① 登记 / 更新策略（账户给模块登记，走 ROOT）</p>
          <div className="space-y-1">
            <Label>允许目标 target</Label>
            <Input
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              placeholder="0x..."
              className="font-mono text-xs"
            />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <Label>单笔上限 (ETH)</Label>
              <Input value={cap} onChange={(e) => setCap(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>有效期 (分钟,0=永不)</Label>
              <Input value={ttl} onChange={(e) => setTtl(e.target.value)} />
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={!pk || !canRegister} onClick={register}>
              <ShieldCheck /> 登记 / 更新 session
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={!pk || !canRegister || !policy?.exists}
              onClick={revoke}
            >
              <Trash2 /> 撤销
            </Button>
          </div>
        </div>

        <div className="space-y-2 rounded-lg border p-3">
          <p className="text-xs font-medium text-muted-foreground">② 用 session key 签名并提交（纯 ETH 转账）</p>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_110px]">
            <div className="space-y-1">
              <Label>收款地址</Label>
              <Input value={sendTo} onChange={(e) => setSendTo(e.target.value)} className="font-mono text-xs" />
            </div>
            <div className="space-y-1">
              <Label>金额 (ETH)</Label>
              <Input value={sendAmt} onChange={(e) => setSendAmt(e.target.value)} />
            </div>
          </div>
          <Button variant="secondary" className="w-full" disabled={!pk || !canSend} onClick={send}>
            <Send /> 用 session key 签名并发送
          </Button>
          {canConfig && !policy?.exists && (
            <p className="text-xs text-muted-foreground">先登记策略后才能用 session key 发送。</p>
          )}
          <p className="text-xs text-muted-foreground">
            试越界：把金额改到超过上限、或把收款地址换成白名单外的地址 → 链上 validateExecution 会拒绝整笔。
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
