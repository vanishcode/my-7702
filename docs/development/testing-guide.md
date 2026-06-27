# 测试指南 / Testing Guide

## 运行测试

```bash
forge test -vvv
```

## P256 预编译与测试 Vendor

- 本地 prague EVM **不带** `0x100` P256 预编译。
- 测试在 `0x100` 地址 etch 一个自包含 verifier：`test/vendor/P256Verifier.sol`（来自 [Daimo](https://github.com/daimo-eth/p256-verifier)）。
- 生产代码 `src/` **零第三方依赖**；vendor 文件仅用于测试。

## 对抗性测试

新增安全相关逻辑时，请在 `test/Security.t.sol` 中补充对抗性测试，覆盖：

- 权限绕过
- 重放攻击
- 签名可塑性
- 重入攻击
- 模块隔离失效
