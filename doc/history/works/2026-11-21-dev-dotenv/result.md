---
layer: history
module: global
status: frozen
updated: 2026-11-23
---

# 2026-11-21 开发环境凭据文件 — 收口

## 结论

启动配置来源为：DEBUG 环境（仅 DEBUG 构建）→ `~/.uumail.env` → 登录 Keychain。文件只在
「开发 → 保存凭据到 ~/.uumail.env」菜单动作时写入（`0600`、明文），读到完整配置即不再访问钥匙串；
删除文件回到 Keychain 流程。

## 验收

- `DotEnvCredentialStoreTests` 4 例（round-trip、`0600`、注释/引号/`export` 解析、缺字段回落、特殊字符）。
- `ConfigurationSourceTests` +3（文件优先且不碰 Keychain、残缺回落、路径覆盖）。
- `AppCompositionTests` +1（nil 配置 → `connect()` → 导出可读回账号/设备）。
- 全量 `376 tests / 59 suites` 绿；架构 4 门 PASS。

## 结论落点

| 结论 | 落点 |
|---|---|
| 决策、安全边界与未采纳方案 | `history/decisions/2026-11-21-dev-dotenv-credentials.md` |
| 配置源与平台适配器 | `design/components/CMP-ROOT/spec.md` §设计增量 |
| 架构对象图 | `design/architecture.md` §6.1 |
| 使用说明 | `README.md` 开发机免弹窗 |
| 提交 | `46dd064`（功能）、`49d1421`（setup 后配置留存）、`f009a82`/`271076b`（重发 dist） |

## 残余

- 首次启动仍需 Keychain 授权一次（按设计）；文件是明文，靠 `0600` + FileVault，需避免提交/同步备份。
