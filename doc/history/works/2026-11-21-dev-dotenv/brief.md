---
layer: history
module: global
status: frozen
updated: 2026-11-23
---

# 2026-11-21 开发环境凭据文件 ~/.uumail.env（T-1121-07）

> 已归档（2026-11-23）。现行真相见 `design/components/CMP-ROOT/spec.md` 与
> `history/decisions/2026-11-21-dev-dotenv-credentials.md`。

**问题**：`dist/uumail.app` 是 ad-hoc 签名，`make-app.sh` 重签后系统视为新程序，启动访问
`com.uumail.account` 必弹钥匙串授权，开发调试每次都要输登录密码。

**决定（用户 2026-11-21）**：应用启动优先读 `~/.uumail.env`，读到完整配置就不碰钥匙串；
只在菜单「开发 → 保存凭据到 ~/.uumail.env」显式导出；所有构建都读。

**实现**：`DotEnvCredentialStore`（`0600` 原子写、缺字段静默回落）、`ConfigurationSource` 顺序
DEBUG 环境 → `~/.uumail.env` → Keychain、`AppComposition.saveDevelopmentCredentials()` + `DeveloperCommands`、
`connect()` 后保留配置。
