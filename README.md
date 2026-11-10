# uumail

macOS 原生邮件客户端，只走 Exchange ActiveSync（以「一台已登记的 iPhone」身份接入公司 Exchange）。

## 状态（v0.1）

v0.1 只承诺一件事：**邮件能读、能发**。账号接入、收件箱同步、HTML 正文阅读、发信（`SendMail`）与附件下载已在真实网关上跑通，见 [`doc/design/components/CMP-EAS/playbook.md`](doc/design/components/CMP-EAS/playbook.md) 的实测记录。

架构仍是过渡形态，别按它的现状写新功能：顶层组合分裂在视图、`MailboxModel`、`MailService`、`MailStore` 四处，EAS 只在同步路径上被端口隔离，正文/附件/发送三处直连客户端。按**场景**收口的 P1 重构规格与第二轮评审已在 [`doc/works/2026-11-10-scene-refactor/`](doc/works/2026-11-10-scene-refactor/) 待执行。

发布物是 `dist/uumail.app`（ad-hoc 签名），`dist/build-info.txt` 记录对应的 commit 与构建时间。

## 结构

```
Package.swift        Swift 6 包（EASClient / MailStore / SyncEngine / AppServices / uumail / uumailctl）
Sources/             代码
Tests/               测试
doc/                 文档根（需求、计划、设计、工序、历史五态）
dist/                每个开发里程碑发布一次 uumail.app（构建产物，不入库）
```

## 文档入口

[`doc/README.md`](doc/README.md) —— 阅读顺序与当前状态。文档树内路径均相对 `doc/`。

## 构建与测试

```bash
./Scripts/swiftw build
./Scripts/swiftw test
./Scripts/swiftw run uumailctl diagnose
./Scripts/make-app.sh && open dist/uumail.app   # 构建并发布到 dist/
```

`Scripts/swiftw` 只是把三件本机必须的事包起来：SwiftPM 缓存放进 `.build/`、关闭嵌套 sandbox、固定 scratch 路径。直接用 `swift build` 会让 clang 模块缓存写到工作区外而被拒。

## 真机验证（只读）

凭据不落在本仓库：探针目录的 `.env` 已复制一份到仓库根的 `.env`（已 gitignore，权限 600），需要在别的 session 里重跑时先加载它：

```bash
set -a; . ./.env; set +a          # EAS_HOST / EAS_USER / EAS_PASS / EAS_DOMAIN / EAS_DEVICE_ID
./Scripts/swiftw run uumailctl diagnose
./Scripts/make-app.sh && open dist/uumail.app   # 构建并发布到 dist/
```

`.env` 只留在本机：不提交、不外发。探针原始副本仍在 `~/working/公网邮箱访问/.env`。

`diagnose` 只发 `OPTIONS → Provision → FolderSync`，不改服务器数据。

调试启动（仅 DEBUG 构建，不写 Keychain）：在同一个 shell 里再加

```bash
UUMAIL_DEBUG_ENV=1 UUMAIL_DB_PATH="$PWD/.build/app.sqlite" .build/debug/uumail
```

首次配置写进 Keychain 后，`dist/uumail.app` 启动即自动同步：

```bash
set -a; . ./.env; set +a
./Scripts/swiftw run uumailctl seed
security delete-generic-password -s com.uumail.account   # 需要撤销时
```

应用数据在 `~/Library/Application Support/uumail/mail.sqlite`；`dist/` 只放应用包。

原始协议探针（Python）留在 `~/working/公网邮箱访问`，只作证据，不是本仓库的一部分。
