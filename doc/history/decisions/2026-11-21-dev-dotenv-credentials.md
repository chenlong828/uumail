---
layer: history
module: global
status: frozen
updated: 2026-11-21
---

# 开发环境凭据文件 `~/.uumail.env`（2026-11-21）

## 背景

`dist/uumail.app` 是 ad-hoc 签名，每次 `make-app.sh` 重新签名后系统把它当成新程序，
访问登录钥匙串的 `com.uumail.account` 会再次弹「uumail 想要使用你储存在钥匙串中的机密信息」。
发布调试时每次启动都要输一次登录密码，打断开发循环；普通用户首次授权一次即可，不受影响。

## 决定

- 新增开发者凭据文件 `~/.uumail.env`（`KEY=VALUE`，权限 `0600`）。应用启动时**优先读取它**；
  读到完整配置就不再访问钥匙串，读不到（不存在/缺字段）才回落到 Keychain。
- **所有构建都读**（含 `dist` 发布版）：开发机免弹窗，普通用户不创建该文件则行为不变。
- **只在用户显式操作时写**：菜单「开发 → 保存凭据到 ~/.uumail.env」调用
  `AppComposition.saveDevelopmentCredentials()`，用当前已保存的配置生成文件；应用不会在启动/同步时自动写。
- 字段：`EAS_HOST`、`EAS_USER`、`EAS_PASS`、`EAS_DOMAIN`、`EAS_DEVICE_ID`、`EAS_DISPLAY_NAME`
  （与仓库根 `.env`、CLI 的变量名一致，可直接给 `uumailctl` 用）。`UUMAIL_DOTENV_PATH` 可改路径（测试/多环境）。
- 读取顺序：DEBUG 环境（仅 DEBUG 构建，`UUMAIL_DEBUG_ENV=1`）→ `~/.uumail.env` → 登录 Keychain。

## 安全边界

- 文件是**明文密码**，靠文件权限（0600）+ FileVault + 用户自律；不进仓库、不进日志、不进备份说明。
- 只由明确的菜单动作生成；启动路径永远不写文件，普通用户不会被默默落一份明文。
- 删除 `~/.uumail.env` 即回到 Keychain 授权流程。
- 文件损坏/字段不全时静默回落 Keychain，不显示错误（避免把半成品文件当成配置错误）。

## 未采纳

| 方案 | 理由 |
|---|---|
| 首次解锁后自动写文件 | 普通用户会被动把明文密码落盘，超出「开发便利」范围 |
| 仅 DEBUG 构建读取 | 用户实际调试的是 release `dist/uumail.app`，解决不了弹窗 |
| 放宽 Keychain ACL / 自签名稳定标识 | 每次重新 ad-hoc 签名身份都会变，ACL 方案在当前构建流程下不可稳定 |
| 把密码写进 `UserDefaults` 或应用支持目录 | 同样明文，且有被备份/同步带走的额外风险 |

## 人工确认记录

2026-11-21 用户选择：① 菜单项手动导出（不自动写）；② 所有构建都读 `~/.uumail.env`。

定级 **P2**（安全相关的配置来源变更；不改 schema/公开业务契约）。
