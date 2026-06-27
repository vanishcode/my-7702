# 快速开始 / Quickstart

## 环境要求

- [Foundry](https://book.getfoundry.sh/)
- Solidity `0.8.28`，EVM `prague`，`via_ir = true`

## 命令速查 / Commands

```bash
# 构建 / build
forge build --sizes

# 测试 / test
forge test -vvv

# 格式化（CI 会 --check）/ format
forge fmt
```

> 改动后务必先 `forge fmt && forge test`。
