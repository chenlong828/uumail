---
layer: requirements
module: mail
scope: project:uumail
status: delivered
updated: 2026-11-24
---

# REQ-0038 发件箱显示服务器 Sent Items

- **ID**：REQ-0038
- **类型**：`feature`
- **场景叙述**：用户点顶部「发件箱」，列表先显示本地已缓存的已发送邮件，随后按服务器 Sent Items（Exchange folder type 5）同步最近 30 天，服务器上的已发送副本进入列表。用户发送成功的信，由 `SendMail` 既有的 `SaveInSentItems` 落到服务器；用户下次打开「发件箱」时，同步把副本拉回来。账号没有 Sent 文件夹时，发件箱显示「没有发件邮件」空态，不报错；同步失败时保留已有列表并给出中文错误，收件箱的列表与同步状态不受影响。
- **价值**：不做的后果——现在发送成功的信只在服务器 Sent Items 里，本地同步只取收件箱（type 2），用户点「发件箱」永远看到空列表，会以为发送失败或客户端把信丢了。本地再写一份 Sent 镜像会引入第二真相、重复与清理问题；服务器已有 `SaveInSentItems`，把 type 5 作为只读集合纳入按需同步，就能让用户核对「我到底发出去什么」，且不改发送路径。
- **非目标**：
  - 不做本地 Sent 镜像，不在发送成功时重复写本地或服务器；服务器副本由既有 `SaveInSentItems` 负责。
  - 不做发送成功后的即时 Sent 同步；用户打开「发件箱」时才同步。
  - 不同步草稿、已删除、垃圾邮件等其他文件夹，也不为它们提供入口（导航口径见 `REQ-0037`）。
  - 不做发件箱附件、搜索或工具栏的特殊化；沿用阅读、附件、搜索与工具栏的既有能力。
  - 不改 `SendMail` 请求、EAS 协议、outbox 状态机、schema、target 或依赖。
- **约束**：
  - **只读服务器 Sent Items**：只把 type 5 的同步批次写入本地，不新增发件箱写路径；`syncOnce()` 仍只同步收件箱。
  - **不动收件箱 key/窗口**：Sent 使用自己 collection 的 sync key（`sync_state` 按 collection 存），同步 Sent 不推进、不重置收件箱 key，也不改收件箱的 30 天读取窗口。
  - **失败隔离**：Sent 同步失败映射为发件箱的刷新失败，显示中文错误并保留缓存列表，**不判成收件箱失败**；错误可重试。
  - **不新增新邮件通知**：Sent 同步不触发「新邮件」通知；自己的发件不是来信。
  - 打开「发件箱」时先显示缓存，再同步；同步窗口与列表一致为最近 30 天（`FilterType=5`）。
  - 无 Sent 文件夹 → `syncSentOnce` 返回 nil，发件箱显示「没有发件邮件」空态，不出现错误文案。
  - `SendMail` 继续携带 `SaveInSentItems`，EAS 与 `SendMail` 请求不改；本卡只消费服务器已保存的副本。
  - 不改 schema、target、依赖。
- **影响场景**：
  - **新建 `SCN-0029`（`mail/send/sent-items`）**：认领「只同步 Sent 且不动收件箱 key」「selectSent 选中/刷新/出现副本」「SendMail 携带 `SaveInSentItems`」「无 Sent 空态与失败保留缓存」的 3 正 1 反。
  - 回归（不新增断言，不作为本卡验收证据）：`SCN-0025`（双击/浮窗阅读）、`SCN-0024`（日历）、`SCN-0027`（列表宽度口径）。
- **澄清记录**：
  - 2026-11-24 **人工确认**：发件箱**显示服务器 Sent Items（folder type 5）**，不建本地 Sent 镜像。
  - 2026-11-24 **人工确认**：把 Sent Items **纳入同步**；打开「发件箱」时按 type 5 拉取该集合。
  - 2026-11-24 **人工确认**：草稿、已删除、垃圾邮件等其他文件夹仍隐藏、不提供入口，本次不同步。
  - 2026-11-25 **已验证**：真实发信第一次因 `From` 为 `账号@mail.hundsun.com` 被网关 502；按 `REQ-0039` 改用 `EAS_EMAIL` 后发送成功，`uumailctl sync-sent` 从服务器 Sent Items 拉到 12 封（含测试信）。App 的「发件箱」走同一条 `syncSentOnce` 路径；真实 App 点击仍列为发布前人工项。
- **状态**：`delivered`（2026-11-24 实现并验证：`SCN-0029` verified；L1 `SyncEngineTests` 2 例 + `MailboxViewModelTests` 1 例 + 既有 `EASClientTests` 的 `SaveInSentItems` 断言；465 tests / 77 suites、架构 4/4；`make-app.sh` 成功（release）。真实发信在修正地址后成功、服务器 Sent Items 可拉取；App 内点击发件箱的整窗冒烟仍待人工）
- **验收归属**：`SCN-0029` 的 3 正 1 反通过 + 上述约束逐条无违反 + 回归场景不退化；需求不另立测试。
