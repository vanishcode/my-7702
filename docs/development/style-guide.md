# 代码风格 / Style Guide

## 注释 / Comments

- 注释为中英双语 / comments are bilingual (Chinese + English)。
- 公共接口需包含中文简述与英文简述。

## 格式 / Formatting

- 使用 `forge fmt` 自动格式化。
- 配置项见 `foundry.toml`：
  - `line_length = 120`
  - `tab_width = 4`
  - `bracket_spacing = false`
  - `int_types = "long"`
- CI 会执行 `forge fmt --check`，提交前请先本地格式化。
