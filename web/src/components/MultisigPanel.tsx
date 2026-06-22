import {useEffect, useState} from "react";
import {isAddress, parseEther, type Address, type Hex} from "viem";
import {RefreshCw, Send, ShieldCheck, Trash2, Users} from "lucide-react";
import {toast} from "sonner";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Badge} from "@/components/ui/badge";
import {Input} from "@/components/ui/input";
import {Label} from "@/components/ui/label";
import {
  addrOf,
  genMultisigSignerPks,
  getMultisigConfig,
  isModuleInstalled,
  loadMultisigSignerPks,
  saveMultisigSignerPks,
  sendMultisigExecute,
  setMultisigConfig,
  sortSignerPks,
  type Call,
  type MultisigConfig,
} from "@/lib/account";
import {ADDR, isDeployed} from "@/lib/contracts";
import {runTx} from "@/lib/tx";
import {shortAddr} from "@/lib/utils";

const DEMO_TARGET = "0x6ab1d676904b232fa27e0cd9a1592759c5954eff";
const SIGNER_COUNT = 3; // 演示固定生成 3 把联签私钥 / demo generates 3 co-signer keys

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  refreshKey: number;
  bump: () => void;
}

export function MultisigPanel({pk, account, delegated, refreshKey, bump}: Props) {
  const deployed = isDeployed(ADDR.multisigValidator);

  const [signerPks, setSignerPks] = useState<Hex[]>([]);
  const [moduleInstalled, setModuleInstalled] = useState<boolean | null>(null);
  const [config, setConfig] = useState<MultisigConfig | null>(null);

  const [m, setM] = useState("2"); // 阈值 M / threshold
  const [sendTo, setSendTo] = useState(DEMO_TARGET);
  const [sendAmt, setSendAmt] = useState("0.0005");

  useEffect(() => {
    let alive = true;
    if (!account) {
      setSignerPks([]);
      setModuleInstalled(null);
      setConfig(null);
      return;
    }
    setSignerPks(loadMultisigSignerPks(account)); // 本地联签私钥（升级前也可先生成查看）
    if (!delegated || !deployed) {
      setModuleInstalled(null);
      setConfig(null);
      return;
    }
    isModuleInstalled(account, 1, ADDR.multisigValidator).then((v) => alive && setModuleInstalled(v));
    getMultisigConfig(account).then((c) => alive && setConfig(c.exists ? c : null));
    return () => {
      alive = false;
    };
  }, [account, delegated, deployed, refreshKey]);

  const signerAddrs: Address[] = signerPks.map(addrOf);

  function genKeys() {
    if (!account) return;
    saveMultisigSignerPks(account, genMultisigSignerPks(SIGNER_COUNT));
    bump();
    toast.success(`已生成 ${SIGNER_COUNT} 把演示联签私钥（仅存浏览器本地）`);
  }

  async function configure() {
    if (!pk || signerPks.length === 0) return;
    const threshold = Math.floor(Number(m || "0"));
    if (!Number.isFinite(threshold) || threshold < 1 || threshold > signerPks.length) {
      return toast.error(`阈值需在 1..${signerPks.length} 之间`);
    }
    await runTx(
      `配置 ${threshold}-of-${signerPks.length} 多签`,
      () => setMultisigConfig(pk, sortSignerPks(signerPks).map(addrOf), BigInt(threshold)),
      bump,
    );
  }

  /** 用前 `count` 个（按地址升序）联签私钥签名并提交 / sign with the lowest `count` co-signers. */
  async function send(count: number) {
    if (!pk || !account || !config) return;
    if (!isAddress(sendTo)) return toast.error("收款地址格式错误");
    let value: bigint;
    try {
      value = parseEther((sendAmt || "0").trim());
    } catch {
      return toast.error("金额格式错误");
    }
    const usable = sortSignerPks(signerPks).slice(0, count);
    const calls: Call[] = [{target: sendTo as Address, value, data: "0x"}];
    const label = count >= Number(config.threshold) ? `多签授权交易（${count} 签）` : `故意只用 ${count} 签（应失败）`;
    await runTx(label, () => sendMultisigExecute(pk, usable, calls), bump);
  }

  const canConfig = deployed && delegated && moduleInstalled === true && signerPks.length > 0;
  const canSend = canConfig && !!config?.exists;
  const M = config ? Number(config.threshold) : 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Users className="size-4" /> ⑥ Multisig 多签（M-of-N）
        </CardTitle>
        <CardDescription>
          M-of-N 多签验证器（type-1 validator）：一笔执行需 ≥M 个登记签名者各对同一 execHash 签一份（secp256k1，强制
          low-s、严格升序去重）。多签可授权对外转账/调用，但
          <span className="font-medium text-foreground">永远无法触达账户自身(admin)</span>
          ——核心在非 ROOT 路径强制拦截，EOA ROOT 私钥仍是最终管理员。演示把 N 把联签私钥都放浏览器本地以便单机凑齐 M 份签名。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!deployed && (
          <p className="text-sm text-destructive">
            MultisigValidator 尚未部署到本链。先运行 <code className="text-xs">script/Deploy.s.sol</code>
            ，再把地址写进 <code className="text-xs">web/.env</code> 的 <code className="text-xs">VITE_MULTISIG_VALIDATOR</code>。
          </p>
        )}
        {deployed && !delegated && <p className="text-sm text-muted-foreground">需先完成 7702 升级。</p>}
        {deployed && delegated && moduleInstalled === false && (
          <p className="text-sm text-muted-foreground">需先在「② 插件商店」安装 MultisigValidator。</p>
        )}

        {/* 联签私钥集合 / co-signer key set */}
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted-foreground">联签人：</span>
          {signerAddrs.length ? (
            signerAddrs.map((a) => (
              <Badge key={a} variant="secondary" className="font-mono">
                {shortAddr(a)}
              </Badge>
            ))
          ) : (
            <Badge variant="outline">未生成</Badge>
          )}
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            disabled={!account}
            onClick={genKeys}
            title="生成 / 重置联签私钥"
          >
            <RefreshCw />
          </Button>
          {config?.exists ? (
            <Badge variant="success">
              已配置 {M}-of-{config.signers.length}
            </Badge>
          ) : (
            <Badge variant="outline">未配置</Badge>
          )}
        </div>

        {config?.exists && (
          <div className="space-y-0.5 rounded-lg border border-dashed p-2 text-xs text-muted-foreground">
            <div>阈值 M：{M}</div>
            <div>
              登记签名者（{config.signers.length}）：
              <span className="font-mono">{config.signers.map((t) => shortAddr(t)).join(", ")}</span>
            </div>
          </div>
        )}

        {/* ① 配置 / configure */}
        <div className="space-y-2 rounded-lg border p-3">
          <p className="text-xs font-medium text-muted-foreground">① 配置 / 更新多签（账户给模块登记，走 ROOT）</p>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <Label>阈值 M（1..{signerPks.length || SIGNER_COUNT}）</Label>
              <Input value={m} onChange={(e) => setM(e.target.value)} />
            </div>
            <div className="flex items-end">
              <span className="text-xs text-muted-foreground">
                签名者数 N = {signerPks.length || 0}（即上面的联签人）
              </span>
            </div>
          </div>
          <Button size="sm" disabled={!pk || !canConfig} onClick={configure}>
            <ShieldCheck /> 配置 / 更新多签
          </Button>
          {deployed && delegated && moduleInstalled === true && signerPks.length === 0 && (
            <p className="text-xs text-muted-foreground">先点上面的刷新图标生成联签私钥。</p>
          )}
        </div>

        {/* ② 使用 / use */}
        <div className="space-y-2 rounded-lg border p-3">
          <p className="text-xs font-medium text-muted-foreground">② 用多签签名并提交（纯 ETH 转账）</p>
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
          <div className="flex flex-wrap gap-2">
            <Button variant="secondary" disabled={!pk || !canSend} onClick={() => send(M)}>
              <Send /> 用 {M || "M"} 份签名发送
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={!pk || !canSend || M < 2}
              onClick={() => send(M - 1)}
              title="故意只用 M-1 份签名，链上 validateExecution 应拒绝整笔"
            >
              <Trash2 /> 试错：只用 {M > 0 ? M - 1 : "M-1"} 份（应失败）
            </Button>
          </div>
          {canConfig && !config?.exists && (
            <p className="text-xs text-muted-foreground">先配置多签后才能签名发送。</p>
          )}
          <p className="text-xs text-muted-foreground">
            签名者是 N 把本地联签私钥、提交者是 burner EOA（自付 gas，任意地址可提交）。把收款地址改成账户自身 →
            核心层会以 SelfCallNotAllowed 拦截（多签也碰不到 admin）。
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
