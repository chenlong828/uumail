---
layer: history
module: global
status: frozen
updated: 2026-11-24
---

# 风险收口与登记复核（2026-11-24）

## 背景与判定口径

2026-11-24 对 `plan/risks.md`（R1–R69）与 `plan/open-questions.md`（Q1–Q7）做一次全量复核。
触发原因：R1–R69 是跨 16 个工序逐批追加的，早期「设计已处置」「实现已完成」「已接受限制」混在同一张表里，
到了 W-M3-17（浮动阅读窗）开工前，已经无法从表上看出哪些风险真的消了、哪些只是设计过、哪些还欠着。

判定规则：

- **已关闭**：触发条件消失，或缓解已实现并有 `verified` 场景/测试覆盖，且没有待办残余。
- **仍存在**：留在 `plan/risks.md`，按处理方式分「待拍板 / 处置中 / 已接受 / 外部监控」四组。
- **不把「设计已确认」写成「已实现」**，**不把「已接受限制」写成「已修复」**。
- 行号与测试名以 2026-11-24 工作区实测为准；场景状态以 `design/scenarios/**/scenario.md` frontmatter 为准。

本轮同时做了一次代码/预算实测，发现的问题单列在第三节，不混进「已关闭」。本文是 2026-11-24 复核时点的快照；
当日晚些时候的逐项拍板结论见 `2026-11-24-risk-review-decisions.md`，两者冲突时以后者为准。

## 一、已关闭（移出 `plan/risks.md`）

| ID | 原风险摘要 | 关闭依据 | 证据 |
|---|---|---|---|
| R14 | 网关 Sync 信封不返回 `Cc`，全部回复无法预填抄送 | 真机回放确认返回 `Cc`，`REQ-0012` 已交付 | `CMP-EAS/playbook.md` §5.3；`SCN-0007` `verified` |
| R15 | v9 回填只覆盖最近窗口，升级后首同步可能多发一次通知 | 范围限定为「最近同步窗口」，不伪造更早邮件；一次性通知为已接受副作用 | `REQ-0012` `delivered`；`CMP-STORE/spec.md` v9 增量 |
| R16 | 网关是否接受 `Sync` 写命令（`Read=1`、`Delete`）未验证 | 真机证两项均 `Collection/Status=1` + 新 key，删除进「已删除邮件」 | `task-spaces/20261114-232232/evidence/r16-real-gateway.txt`；`SCN-0008`/`SCN-0009` `verified` |
| R17 | `MailboxViewModel` 超 400 行预算 | 拆出 Dwell/Deletion/Compose/Delete/Body 后主文件 298 行 | `CMP-PRES/spec.md` 实现记录；**注：2026-11-24 又长到 424 行，另立 R70** |
| R19 | 两个 `SyncEngine` 或写命令与 `syncOnce` 交错，导致 key 回退/丢变更 | 一账号一引擎 + 显式 FIFO 门，`syncInbox` 门内重读 key；并发用例已补 | `AppComposition.swift` 单引擎装配；`CMP-SYNC/spec.md`；`SCN-0008`/`SCN-0009` `verified` |
| R20 | 写响应携带其它变更/`MoreAvailable`，或删除 not-found 状态未定义 | 写响应 delta 与本地效果/key 同事务提交，剩余页下轮消费；重复删除为成功 no-op | 真机证据同上；`SCN-0008`/`SCN-0009` `verified` |
| R22 | 非可选写端口使改动跨 `CMP-ROOT`，组件边界被破坏 | 已固化为批次规则：组件列写 `+CMP-ROOT（仅装配）`，该 change 独占 `CMP-ROOT` WIP | `architecture.md` §3.1/§10；`roadmap.md` 批次纪律 |
| R23 | 搜索/选择身份只按 `serverID`，跨文件夹同 ID 可能命中错邮件 | 列表/选择改用复合 `listKey`（folder + serverID），公开类型不变；两条跨文件夹用例已绿 | `Tests/PresentationTests/MailboxViewModelTests.swift` `crossFolderSameServerID` / `...UsesCompositeIdentity`；`SCN-0009` `verified` |
| R24 | `WKWebView.appearance` 被系统重置，深色下白底失效 | 创建时设常量、`updateNSView` 复确认 | `Sources/uumail/MessageBodyView.swift`（`appearance` 赋值与复确认）；`SCN-0010` `verified` |
| R26 | 菜单勾选只在父菜单打开时刷新，静止读取得到旧值 | 测试先打开父菜单再读 `state`，已写入 `SCN-0011` 测试说明 | `SCN-0011` `verified` |
| R27 | 阅读页头部过长把正文挤出可视区 | 头部行数/宽度上限 + 正文可滚动，L2 已按长头部夹具验 | `SCN-0012` `verified`；`task-spaces/20261116-212545/evidence/header-probe/` |
| R28 | 切换邮件时头部与正文状态不同步 | 头部唯一来源 `selectedMessage`，`.none` 两义收口，慢正文/切换断言已绿 | `SCN-0012` `verified` |
| R29 | 无头探针读不到 SwiftUI 文本，L2 无法验收 | 已证可选 `Text` 由 `NSTextField` 承载、`stringValue` 即渲染文本 | 同上 header probe；`SCN-0012` `verified` |
| R32 | 工具栏 7 项在 900×560 下拥挤/溢出 | 紧凑图标 + 探针在 900×560 含搜索框下 7 项全可见、无溢出 | `SCN-0013`/`SCN-0014` `verified`；`task-spaces/20261116-223645/evidence/toolbar-probe/` |
| R33 | 远程图片放行状态跨邮件泄漏 | 状态归 VM，`selectedListKey` 变化重置，setter 受 `canAllowRemoteContent` 守卫 | `SCN-0013` `verified`；L1 `remoteContentResetsOnSelectionChange`/`...CannotLeakToStaleBody` |
| R34 | 自动已读 3 秒会在用户只扫一眼时置读 | 3 秒为发起人明确要求，前台/选中/非搜索三条件，切走/失活即取消；已按 3 秒重验 | `SCN-0008` `verified`；`MailboxDwell.swift:11` |
| R35 | 手动置读与自动计时并发，重复网络写 | 自动/手动共用 `performMarkRead`，只有真实 0→1 回写；断言恰好一次 | `SCN-0014`/`SCN-0008` `verified`；`task-spaces/20261117-064420/review.md` §7 |
| R36 | SwiftUI `.toolbar` 项在无头宿主不可读，位置无法 L2 | 离屏 `NSHostingController` + `NSWindow` 可读 `NSToolbar.items` 并合成点击 | `task-spaces/20261116-223645/evidence/toolbar-probe/`；`SCN-0013`/`SCN-0014` `verified` |
| R38 | 本地置读失败抛非 `MailError`，中文提示契约假绿 | `performMarkRead` 归一为 `MailError.storage`，补非 `MailError` 用例 | `SCN-0014` `verified`；`task-spaces/20261116-223645/design.md` §7.9 |
| R39 | 界面字号缩放与显式 `.font` 冲突 | 环境值 + `scaledFont`/`scaledInheritedFont`，100% 恒等分支，覆盖清单已落 | `SCN-0015` `verified`；`history/decisions/2026-11-17-font-size*.md` |
| R40 | 正文缩放不覆盖作者 `px`，或放大图片/表格溢出 | 改用 `WKWebView.pageZoom`，作者 px/图片/表格随整页缩放，白底/CSP/禁 JS 不变 | `SCN-0015` `verified`；`task-spaces/20261117-095147/review.md` |
| R41 | 225% 下布局溢出/控件不可操作 | 元数据区 cap 220pt 并内部滚动，正文视口 259pt，7 动作可见 | `SCN-0015` `verified`；同上 |
| R42 | 100% 恒等档回归 | 100% 不装根 `.font`、不包 cap，L2 基线断言已绿 | `SCN-0015` `verified` |
| R43 | L2 文本/正文度量 seam 不可行 | 设计期证 seam，实现期生产源复跑，L2 342/0 | `SCN-0015` `verified`；`task-spaces/20261117-095147/review.md` |
| R44 | 字号偏好写失败/启动闪烁/与主题耦合 | 会话状态为真源、独立 key、首帧读取、父菜单打开再读勾选 | `SCN-0015` `verified` |
| R47 | 候选浮层探针读不到行文本/被遮挡 | `.overlay` 不参与布局 + `zIndex`，行/字段/点击探针已绿 | `SCN-0017` `verified`；`task-spaces/20261118-082503/evidence/design-probe/overlay-probe.txt` |
| R48 | 点击候选行先失焦导致选不中 | `suggestionClickInFlight` 延后失焦清空，点击用例已绿 | `SCN-0017` `verified`；`task-spaces/20261119-164437/review4.md` |
| R50 | 名字加宽后邮箱列只能显示 `h…@c` 级形态 | 改为「保留 `@` 两侧」的显式缩短 + `fullAddress` 兜底，175%/225% 断言语义已钉住 | `REQ-0023` `delivered`；`SCN-0017` `verified`；`task-spaces/20261119-164437/design2.md` §4 |
| R51 | 交付载体 plist 丢失 ATS 键，远程图片静默失效 | plist 单一来源 + `make-app.sh` 只 `cp`，`plutil`/`cmp`/脚本接线断言已绿 | `SCN-0018` `verified`；`task-spaces/20261119-213812/review4.md` |
| R52 | 测试用 `127.0.0.1` 判 ATS 或省略负控制 | 非本地主机名 + 无 ATS 负控制 + `data:` 正控制已写入场景与证据 | `SCN-0018` `verified`；`history/decisions/2026-11-19-remote-image-ats.md` |
| R57 | 同一 `UID` 多封邀请乱序，旧时间覆盖新时间 | 写入端按 `dtstamp` 只升不降，取消/过期删行，「先新后旧」负例已钉 | `SCN-0024` `verified`；`MailStore+Meetings.swift` upsert 条件；`T-SCN-0024-04` |
| R63 | 第二个窗口用 SwiftUI `Window` 时默认尺寸/单例替换/置前未证 | 2026-11-24 探针：SwiftUI `Window` 在显示前不能应用计算尺寸，改用 AppKit `NSWindow` + `NSHostingController`（480×707 精确、复用同窗号） | `task-spaces/20261124-152611/probe/`；`CMP-APP` 增量、`SCN-0025` |

R39–R44 的设计处置细节不在此复制，见 `history/decisions/2026-11-17-font-size.md`、`2026-11-17-font-size-round2.md`
与 `task-spaces/20261117-095147/`；R32–R38 的探针细节见 `task-spaces/20261116-223645/`。

## 二、仍存在（留在 `plan/risks.md`）

分组与逐条口径见 `plan/risks.md`：

- **待拍板**：R21、R45、R70、R71、R72、R13、R49、R53、R54、R55、R60、R61、R73；另有 Q1–Q7（`plan/open-questions.md`）。
- **处置中**：R62、R64–R68（W-M3-17，设计完成、待实现）；R63 已由窗口探针关闭并移入上表。
- **已接受**：R4、R5、R7、R8、R9、R10、R12、R25、R30、R31、R37、R46、R56、R58、R59、R69。
- **外部监控**：R1、R2、R3、R11。

R6 与 Q1 同源（本地保留策略），R18 与 Q2 同源（离线队列），不单列。

## 三、本轮复核发现（新增或修正登记）

1. **R21 未真正关闭**：`applyDelta` 只对 `recipients`/`cc`/`preview` 用了 `COALESCE`
   （`Sources/MailStore/MailStore.swift:295-300`），`subject`/`sender`/`received_raw` 仍是 `excluded.*` 直接覆盖；
   现有 `partialChangeKeepsRecipientsAndCc` 只覆盖 To/Cc。服务器只回 `Read` 的 partial `Change` 仍会清空主题/发件人/接收时间。
   这不是已关闭项，转入待拍板。
2. **预算漂移（R45 更新，R70–R72 新增）**：`wc -l` 2026-11-24 实测——
   - `CMP-STORE` 合计 **1152**（`MailStore.swift` 591 + `Migrations.swift` 210 + `MailStore+Meetings.swift` 273 +
     `SyncStoreConformance.swift` 40 + `Values.swift` 38），硬上限 1000，超 **152**；
     `MailStore+Meetings.swift` 设计承诺 ≤120，实为 **273**。规格仍写「约 924」，已失真。
   - `CMP-PRES` `MailboxViewModel.swift` **416**，单文件预算 ≤400（规格记 381）。
   - `CMP-APP` `MailboxView.swift` **305**，单文件预算 ≤300（规格记 219）。
   - `Scenes` 合计 **1294**，拆分触发是「>1200 或出现第二个 HTML 纯工具」；两条同时满足
     （`HTMLText.swift` 221 + `InlineImageHTML.swift` 165），拆分工序尚未立。
3. **R49 没有性能证据**：`Tests/PresentationTests` 没有 5,000 封夹具或首次聚焦耗时记录，设计目标 ≤100ms 未验。
4. **R60 的「缺 `MeetingRequest`」用例不存在**：现有只有 `parsesMeetingRequest` 与 `plainMessageHasNoMeeting`（普通邮件类），
   没有「请求类但缺 `MeetingRequest` 子树」的用例；风险行原先写「已覆盖」不成立，继续留待拍板/补测。
5. **6 张核心场景卡仍是 `designed`**：账号接入、文件夹树同步、收件同步、读信、附件下载、发信。
   功能与 L1 测试存在，但场景卡未转 `verified`；发布前若按「全部场景 verified」口径，会卡在这里。
   另有多项真实窗口/右键/`NSSavePanel`/VoiceOver/像素/A5 真样本冒烟与 `uumailctl diagnose/sync/send` 真机验证未闭环，
   合并登记为 **R73「发布前证据未闭环」**。
6. **R62 状态写错**：`ReadScene.message(_:)`/`MailStore.message(...)` 已由 2026-11-24 决策记录 D12 按 P1 确认
   （`history/decisions/2026-11-24-floating-reader-window.md`），不再是「待确认」，而是「待落规格/实现」。
   `risks.md` 已改为处置中。
7. **R53/R54/R55/R61 是真实欠账，不是已修复**：ATS 载体契约无 CI 守护、像素/解压炸弹 guard 未实现、
   注释/属性值内的 `<img>` 仍会被扫描、WAL 副文件备份只有文字约定。维持「欠账」表述。

## 四、后续约束

- 本轮只做登记重排，不改任何实现；所有「待拍板」项在拍板前按 `plan/risks.md` 的默认走向，不静默改需求。
- 已接受项不得在后续文档里写成「已修复」；要改口径必须重开风险行并留决策记录。
- 预算类风险（R45、R70–R72）未拍板前，W-M3-17 的 `T-1124-17`/`T-1124-19`/`T-1124-20` 不应开工；
  先决定「拆 / 调预算 / 停」。
- 本记录随 `history/` 冻结；后续拍板结论追加在同目录新决策记录，不回头改本表。
