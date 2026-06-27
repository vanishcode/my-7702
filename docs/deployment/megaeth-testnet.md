# 部署到 MegaETH 测试网 / Deploy to MegaETH Testnet

## 链信息 / Chain Info

- Chain ID: **6343**
- RPC: `https://carrot.megaeth.com/rpc`
- 浏览器: `https://testnet-mega.etherscan.io`
- 水龙头: `https://testnet.megaeth.com`

`.env` 需 `PRIVATE_KEY`；验证合约还需 `ETHERSCAN_API_KEY`。

## 部署步骤

```bash
# 0) 确认链 id（避开已废弃的 6342）/ confirm chain id (avoid deprecated 6342)
cast chain-id --rpc-url megaeth_testnet            # 期望 6343

# 1) ⚠️ 先探测 P256 预编译 0x100（passkey 依赖它）/ probe the P256 precompile first
cast call 0x0000000000000000000000000000000000000100 \
  0x4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4da73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d604aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff37618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e \
  --rpc-url megaeth_testnet

# 2) 部署实现与模块 / deploy implementation + modules
forge script script/Deploy.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast

# 3) 委托 EOA 并自调用批量 / delegate the EOA + self-batch
cast send --rpc-url megaeth_testnet --private-key $PRIVATE_KEY \
  --auth <ACCOUNT_IMPL> $EOA <execute calldata> --gas-limit 3000000

# 3') 或用脚本委托并安装一个 validator 插件 / or delegate + install a validator via script
IMPL=<ACCOUNT_IMPL> VALIDATOR=<SESSION_OR_WEBAUTHN_VALIDATOR> \
  forge script script/Delegate.s.sol --rpc-url megaeth_testnet --private-key $PRIVATE_KEY --broadcast

# 4) 验证 / verify (Etherscan v2)
forge verify-contract --chain 6343 --verifier etherscan \
  --verifier-url 'https://api.etherscan.io/v2/api' --etherscan-api-key $ETHERSCAN_API_KEY \
  <addr> src/Account.sol:Account
```

> MegaETH 采用双 gas 模型（普通转账≈60k），7702 交易请给足 `--gas-limit`。
