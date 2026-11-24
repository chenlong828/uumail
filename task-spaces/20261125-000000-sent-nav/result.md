---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-19 结果：顶部邮箱切换与发件箱

## 结论

两项反馈均落地并验证：

1. **顶部三段切换**：去掉左侧文件夹栏，窗口 toolbar 的 leading 位放「收件箱 / 发件箱 / 日历」segmented Picker；邮件页为两栏（列表 480 + 阅读区），日历占满内容区。
2. **发件箱**：服务器 Sent Items（type 5）纳入按需同步；打开「发件箱」时先显示本地缓存，再同步并刷新；`SendMail` 既有的 `SaveInSentItems` 负责让服务器保存副本。
3. 其他文件夹（草稿/已删除/垃圾邮件等）**全部隐藏、不提供入口**，也不再作为同步范围。
4. 全量 **465 tests / 77 suites 全绿**、架构 **4/4**、`make-app.sh` 成功。

## 验收

| 项 | 结果 | 证据 |
|---|---|---|
| 顶部三段、无文件夹栏 | 通过（L2 机制） | `probe/toolbar-nav.png`、`ToolbarProbe.swift` |
| 两栏宽度 | list 480；1440 reading 952、900 reading 412 | `probe/two-column.txt`、`TwoColumnProbe.swift` |
| 发件箱选择与同步 | `selectSent` → folder 18 → 列表出现已发送副本 → phase idle | `MailboxViewModelTests.sentItems` |
| Sent 只同步 Sent | added 2、inbox key 仍 101、无 Sent 返回 nil | `SyncEngineTests.sentItems` / `noSentItems` |
| SendMail 保存副本 | 既有 `<SaveInSentItems/>` 与测试 | `Tests/EASClientTests`（未改） |
| 架构/发布 | 4/4、release 构建成功 | `dist/build-info.txt` |
| 真实发信 + Sent 副本 | 修正地址后成功；服务器 Sent Items 拉到 12 封 | CLI 输出与 `sync-sent` 输出 |
| 邮箱地址配置/迁移 | `ServerConfiguration.email`/`resolvedEmail`、设置页字段、`accounts.address` 迁移、`sync-sent` CLI | 465 tests / 77 suites；`AccountSetupSceneTests.explicitEmail` |

## 残余（发布前人工项）

- **真实发信验证已执行（2026-11-25）**：第一次用本机存储的 `账号@mail.hundsun.com` 被网关 502；改用 `EAS_EMAIL` 后发送成功，`uumailctl sync-sent` 从服务器 Sent Items 拉到 12 封（含测试信）。由此补 `REQ-0039`（邮箱地址配置 + 已存账号地址迁移）。
- 真实点击顶部切换、列表/阅读分隔条拖拽、深色主题整窗视觉。
- 其他文件夹仍不同步；本次按用户选择隐藏，不再提供入口。

## 结论落点

- 需求：`REQ-0037`（顶部切换）、`REQ-0038`（发件箱 Sent Items）与 `REQ-0039`（账号邮箱地址）`delivered`。
- 场景：`SCN-0028`（`mail/receive/mailbox-sections`）、`SCN-0029`（`mail/send/sent-items`）与 `SCN-0030`（`settings/account/mail-address`）`verified`。
- 组件：`CMP-APP`/`CMP-PRES`/`CMP-SYNC`/`CMP-DOMAIN` 增量。
- 计划：`plan/roadmap.md` W-M3-19；`plan/open-questions.md` 的「其他文件夹」项按「隐藏 + 只补发件箱」收口。
