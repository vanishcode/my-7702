import {useState} from "react";
import {formatEther, isAddress, parseEther, type Address, type Hex} from "viem";
import {Layers, Plus, Send, Trash2, Wand2} from "lucide-react";
import {toast} from "sonner";
import {Button} from "@/components/ui/button";
import {Card, CardContent, CardDescription, CardHeader, CardTitle} from "@/components/ui/card";
import {Input} from "@/components/ui/input";
import {Label} from "@/components/ui/label";
import {sendBatch, type Call} from "@/lib/account";
import {runTx} from "@/lib/tx";

interface Props {
  pk: Hex | null;
  account: Address | null;
  delegated: boolean;
  bump: () => void;
}

/** 一行调用的可编辑表单态（都是字符串，提交时再解析）/ editable form state for one call (parsed on submit). */
interface Row {
  target: string;
  value: string; // ETH
  data: string; // 0x...
}

function emptyRow(): Row {
  return {target: "", value: "0", data: "0x"};
}

export function BatchPanel({pk, account, delegated, bump}: Props) {
  const [rows, setRows] = useState<Row[]>([emptyRow()]);

  function patch(i: number, p: Partial<Row>) {
    setRows((rs) => rs.map((r, j) => (j === i ? {...r, ...p} : r)));
  }
  function addRow() {
    setRows((rs) => [...rs, emptyRow()]);
  }
  function removeRow(i: number) {
    setRows((rs) => (rs.length > 1 ? rs.filter((_, j) => j !== i) : rs));
  }

  /** 填一个非破坏性示例：两笔自转账（账户 → 账户自身，净额为 0）/ a non-destructive demo: two self-transfers. */
  function fillExample() {
    if (!account) return;
    setRows([
      {target: account, value: "0.0001", data: "0x"},
      {target: account, value: "0.0002", data: "0x"},
    ]);
  }

  /** 校验并把表单态解析成 Call[]；任一行非法返回 null 并 toast / validate + parse, or null on error. */
  function build(): Call[] | null {
    const calls: Call[] = [];
    for (let i = 0; i < rows.length; i++) {
      const {target, value, data} = rows[i];
      if (!isAddress(target)) {
        toast.error(`第 ${i + 1} 笔：目标地址格式错误`);
        return null;
      }
      let v: bigint;
      try {
        v = parseEther((value || "0").trim());
      } catch {
        toast.error(`第 ${i + 1} 笔：金额格式错误`);
        return null;
      }
      const d = (data || "0x").trim();
      if (!/^0x([0-9a-fA-F]{2})*$/.test(d)) {
        toast.error(`第 ${i + 1} 笔：calldata 须为偶数长度的 0x 十六进制（纯转账填 0x）`);
        return null;
      }
      calls.push({target: target as Address, value: v, data: d as Hex});
    }
    return calls;
  }

  async function send() {
    if (!pk) return;
    const calls = build();
    if (!calls) return;
    await runTx(`批量执行（${calls.length} 笔，原子）`, () => sendBatch(pk, calls), bump);
  }

  // 仅用于展示「总转出」/ display-only running total; ignores rows that don't parse yet.
  const total = rows.reduce((s, r) => {
    try {
      return s + parseEther((r.value || "0").trim());
    } catch {
      return s;
    }
  }, 0n);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Layers className="size-4" /> ⑥ 批量执行 (ERC-7821)
        </CardTitle>
        <CardDescription>
          自发路径 <code>execute(MODE_BATCH, abi.encode(Call[]))</code>：一笔交易原子执行多笔调用，
          <code>msg.sender == address(this)</code> 无需签名，任一笔失败则整批回滚——即 EIP-5792{" "}
          <code>wallet_sendCalls</code> 的链上落点。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!delegated && <p className="text-sm text-muted-foreground">需先完成 7702 升级，EOA 才有 execute 入口。</p>}

        <div className="space-y-3">
          {rows.map((r, i) => (
            <div key={i} className="space-y-2 rounded-lg border p-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-muted-foreground">第 {i + 1} 笔调用</span>
                <Button
                  variant="ghost"
                  size="icon"
                  className="size-7"
                  disabled={rows.length <= 1}
                  onClick={() => removeRow(i)}
                  title="删除这笔"
                >
                  <Trash2 />
                </Button>
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_110px]">
                <div className="space-y-1">
                  <Label>目标地址 target</Label>
                  <Input
                    value={r.target}
                    onChange={(e) => patch(i, {target: e.target.value})}
                    placeholder="0x..."
                    className="font-mono text-xs"
                  />
                </div>
                <div className="space-y-1">
                  <Label>金额 (ETH)</Label>
                  <Input value={r.value} onChange={(e) => patch(i, {value: e.target.value})} />
                </div>
              </div>
              <div className="space-y-1">
                <Label>调用数据 data</Label>
                <Input
                  value={r.data}
                  onChange={(e) => patch(i, {data: e.target.value})}
                  placeholder="0x（纯转账留空为 0x）"
                  className="font-mono text-xs"
                />
              </div>
            </div>
          ))}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" size="sm" onClick={addRow}>
              <Plus /> 添加调用
            </Button>
            <Button variant="ghost" size="sm" onClick={fillExample} disabled={!account} title="填两笔自转账示例">
              <Wand2 /> 填充示例
            </Button>
          </div>
          <span className="text-xs text-muted-foreground">
            共 {rows.length} 笔 · 总转出 {Number(formatEther(total)).toFixed(5)} ETH
          </span>
        </div>

        <Button className="w-full" disabled={!pk || !delegated} onClick={send}>
          <Send /> 一笔发送（原子批量）
        </Button>
      </CardContent>
    </Card>
  );
}
