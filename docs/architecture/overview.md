# 架构总览 / Architecture Overview

## 调用关系 / Call Graph

```
EOA --(7702 type-4 委托)--> Account.sol (delegate singleton, address(this)==EOA)
  ├─ execute(mode, data)            ERC-7821 批量；id1 自发 / id2 opData 签名
  ├─ executeFromExecutor(...)       仅已安装 executor 回调，禁 self-call
  ├─ isValidSignature(...)          ERC-1271：ROOT ecrecover 或路由到 validator
  ├─ install/uninstall/isInstalled  模块注册表（onlySelf）
  └─ 内置 ROOT validator = ecrecover==address(this)
       ├─ WebAuthnValidator (type1)   passkey
       ├─ SessionKeyValidator (type1) session
       ├─ MultisigValidator (type1)   M-of-N 多签
       ├─ ExampleExecutor (type2)     示例
       └─ SpendingLimitHook (type4)   示例
```

## 鉴权优先级 / Auth Precedence

ROOT（`msg.sender==self` 或 root ecrecover）> validator 模块 > executor 模块；hook 仅前后包裹。

## 核心不变式 / Core Invariant

只有 ROOT 路径可 self-call（触达 admin）；session / executor 路径逐笔强制 `to != address(this) && to != address(0)`。

## 文件布局 / Layout

```
src/
  Account.sol                  核心委托单例 / core delegate singleton
  interfaces/                  IERC7579Modules, IERC1271
  lib/                         AccountStorage(ERC-7201), ECDSA, P256, Base64Url, WebAuthn, Types
  modules/                     WebAuthnValidator, SessionKeyValidator, MultisigValidator,
                               SpendingLimitHook, ExampleExecutor
script/                        Deploy.s.sol, Delegate.s.sol
test/                          60+ 测试 + test/vendor/P256Verifier.sol（仅测试用）
```
