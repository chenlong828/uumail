---
layer: plan
module: global
status: draft
updated: 2026-11-14
---

# 风险

只记跨工序风险：触发信号、影响、缓解、落点。单工序内部风险写在该工序 brief 里。

| ID | 风险 | 触发信号 | 影响 | 缓解 | 落点 |
|---|---|---|---|---|---|
| R1 | 网关设备清单被清理或换机 | 所有命令 `200` 空 body、写命令 `401`；短信回执显示设备被删 | 客户端立即不可用，且错误表现为「成功但没数据」，最易误判 | 把「0 字节 200」映射为 `deviceNotRegistered` 并给出登记指引；启动时做一次轻量探活 | `design/components/CMP-EAS/playbook.md` §6 |
| R2 | 公司收紧 EAS 或要求 MDM/零信任客户端 | IT 公告、网关拒绝新设备、`OPTIONS` 不再返回命令列表 | 项目前提失效 | 只走官方移动端通道，不绕过认证；上线前与 IT 确认合规；能力探测失败时明确提示 | `design/architecture.md` §7 |
| R3 | 公司迁移到 Exchange Online / 关闭本地 EAS | IT 公告、账号迁云、本地 EAS 网关下线 | 本项目前提消失：Basic 认证链与新协议均不在范围内 | 项目定位即私有化 Exchange 客户端（T13），不做假兼容；迁移即重新立项评估 | `history/decisions/2026-11-09-scope-baseline.md`、`design/architecture.md` T13 |
| R4 | GAL 与联系人不可用 | `Search`/`Find`/`ResolveRecipients` 非成功状态 | 撰写时无法目录补全，与「企业邮箱体验」预期有落差 | 首版只做本机通讯录 + 收件人历史；UI 不暴露 GAL 入口；能力矩阵标注实测结论 | `design/components/CMP-EAS/playbook.md` §5 |
| R5 | 只支持 5 分钟轮询，新邮件有延迟 | 通知与列表最多晚一个轮询周期 | M3 体验目标（≤60s）在本网关不可承诺 | Ping 实测不支持长轮询（`Status=4`）；固定 5 分钟轮询并在 UI 标注，不做 IMAP 式长连接 | `design/components/CMP-EAS/playbook.md` §5.2、`design/architecture.md` T3 |
| R6 | 大邮箱导致本地库膨胀 | 库文件增长、列表打开变慢、备份失败 | M1 可用性下降 | 按文件夹/时间窗口裁剪正文，列表只保信封；附件 2 GB 最旧优先淘汰 | `design/components/CMP-STORE/spec.md`、`design/components/CMP-APP/spec.md` |
| R7 | HTML 邮件攻击面 | 脚本、远程图片、追踪像素、畸形样式 | 隐私泄露与渲染崩溃 | WKWebView 关脚本 + CSP；默认阻止远程资源；正文经 sanitizer 再渲染 | `design/architecture.md` T5 |
| R8 | 服务器限流 | `503` + `Retry-After`、批量 Sync 变慢 | 同步卡死或账号被临时封禁 | 单账号串行、全局退避、Retry-After 优先；Ping 与 Sync 不并发轰炸 | `design/components/CMP-SYNC/spec.md` |
| R9 | WBXML 编解码边界 | 空元素、code page 切换、NUL 结尾、opaque 长度 | 请求被网关挂起 20s 后 `502`，表现为「网络问题」 | golden fixture round-trip；以探针真实字节为准，不照抄规范写法 | `design/components/CMP-EAS/playbook.md` §4 |
| R10 | 时间与排序错乱 | 列表顺序与服务器不一致、跨时区显示偏差 | 用户找不到新邮件 | 统一以服务器 `DateReceived` 排序，本地接收时间只做兜底 | `design/components/CMP-STORE/spec.md` |
| R11 | 抓包样本含敏感内容 | 真实邮件正文/主题进入仓库或日志 | 合规事故 | 已决：脱敏后入仓（`history/decisions/2026-11-09-scope-baseline.md` 决策记录）；脱敏脚本与样本同目录，`.env`、`logs/`、`output/` 不入库，提交前检查 | `history/decisions/2026-11-09-scope-baseline.md`、`design/architecture.md` §7.3 |
| R12 | 传输与静态数据加固缺口 | 无 certificate pinning；本地库与缓存明文、无 SQLCipher；无审计日志 | 内部 CA 中间人或磁盘/备份泄露时邮件内容暴露 | 凭据只进 Keychain；库与缓存依赖 FileVault；附件名过滤路径分隔符；不做 pinning/SQLCipher 为已知接受项，后续按需补 | `design/components/CMP-STORE/spec.md` 数据所有权、`design/components/CMP-APP/spec.md` |
| R13 | 发送只入队后用户看不出待发/失败 | 离线或投递失败后，列表与状态栏没有 pending/failed 计数；只有撰写页短暂显示「已加入发件箱」 | 用户误以为邮件已发出，重复发送或错过重试 | 组合根已有 `OutboxPump` 自动重投；短期靠撰写页状态文案，后续加列表/状态栏角标（`Outbox.pending` 已可读） | `design/components/CMP-PRES/spec.md`、`CMP-APP/spec.md`、`CMP-OUT/spec.md` |
| R14 | 网关 Sync 信封不返回 `Cc` | `EASClientTests` fixture 或真机样本无 `Cc`；`To` 有值而 `Cc` 恒空 | REQ-0012 的「全部回复填抄送」无法按当前路径交付 | 已关闭（2026-11-14）：T-1114-02 真机 Sync 回放确认网关返回 `Cc`，证据见 `design/components/CMP-EAS/playbook.md` §5.3；后续按 REQ-0012 实现 | `design/components/CMP-EAS/spec.md` 设计增量、`design/scenarios/mail/send/reply-all-recipients/scenario.md` |
| R15 | v9 回填只覆盖最近窗口，且升级后首次同步可能发一次新邮件通知 | 旧库升级后第一次同步；`report.added > 0` 但用户没有新邮件 | 更早邮件 `cc` 为空；一次性通知噪声 | REQ-0012 已把范围限定为「最近同步窗口」；更早邮件不伪造；通知副作用登记为已知接受项，若不可接受另开 CMP-SYNC 任务抑制 | `design/components/CMP-STORE/spec.md` 设计增量、`design/scenarios/mail/send/reply-all-recipients/scenario.md` |
| R16 | 网关是否接受 `Sync` 客户端写命令（`Change` 的 `Read=1`、`Delete`）未验证 | T-1114-12 的录制/真机样本被拒（`Status` 非 1、写命令 `401` 或无 `SyncKey` 返回） | REQ-0013 的服务器已读回写与 REQ-0014 的服务器删除无法按当前路径交付 | T-1114-12 先用录制网关/真机样本证一条 `Read` 变更与一条 `Delete`，并记录响应是否带其它 `Commands`/`MoreAvailable`/逐条状态；确认删除进入「已删除邮件」而非永久删除；被拒则停下重议（`MoveItems` 也未验证，不作默认备胎），不得静默降级为只改本地 | `design/components/CMP-EAS/spec.md`、`design/components/CMP-EAS/playbook.md` §3/§5、`design/scenarios/mail/read/*` |
| R17 | `MailboxViewModel` 已 345/400 行，新增 10 秒计时、删除态与失活处理会超单文件预算 | T-1114-17 实测超过 400 行或组件规格失真 | 展示层文件继续膨胀，评审无法按预算守门 | 设计已定拆分（T-1114-10）：`MailboxDwell.swift`（计时）+ `MailboxDeletion.swift`（隐藏/单飞/错误），现有 Compose 段移到 `MailboxViewModel+Compose.swift`；主 VM 目标 ≤380。T-1114-17 实测超 400 先停下，按流程调预算并记录，不得静默超 | `design/components/CMP-PRES/spec.md` 设计增量、`design/components/CMP-APP/spec.md` |
| R18 | 自动已读/删除只做在线写回，没有离线队列 | 断网时删除失败回滚、已读回写丢失；随后全量重建可能回退本地已读 | 用户感知「删了又回来」「已读又变未读」，与离线可用预期有落差 | REQ-0013/0014 已把范围与失败语义写明；删除失败明确提示可重试，已读本地不丢；T-1114-10 已确认本批不建 `pending_op`/`readDirty`；离线排队仍挂 Q2，若产品要求离线可删则另立工序 | `plan/open-questions.md` Q2、`design/components/CMP-PRES/spec.md`、`design/components/CMP-SYNC/spec.md` |
| R19 | 同一账号出现两个 `SyncEngine`，或写命令与 `syncOnce` 在 actor `await` 处交错，导致同一集合 `SyncKey` 回退/丢变更 | 组合根或场景新建第二个引擎；删除/已读与同步同时发生；`syncInbox` 沿用旧局部 key | 重信/丢信，`Status=3/4` 重建也可能互相顶掉 | T-1114-10 定：一个账号一个 `SyncEngine`，`SyncScene`/`ReadScene` 共用；显式 FIFO 门串行「读 key→一次 Sync→commit」，`syncInbox` 每轮门内重读 key；T-1114-15 补并发测试，T-1114-21 端点装配检查 + T-1114-16 同 engine 注入检查 | `design/components/CMP-SYNC/spec.md` 设计增量、`design/components/CMP-ROOT/spec.md` 设计增量 |
| R20 | Sync 写响应可能携带其它变更/`MoreAvailable`，或删除 not-found 的逐条状态未定义 | T-1114-12 样本出现非空 `Commands`、`MoreAvailable=1` 或无明确 not-found 状态 | 直接推进 key 会跳过未消费变更；把所有错误当成功会误删/误恢复 | T-1114-10 定：写端口返回完整 `MessageDelta`，`commit*` 与本地效果/key 同事务；`moreAvailable==true` 抛 `unsupported`、不提交；not-found 只在样本有明确状态时映射成功；不得静默丢变更或静默当成功 | `design/components/CMP-EAS/spec.md`、`design/components/CMP-SYNC/spec.md`、`design/scenarios/mail/read/keyboard-delete/scenario.md` |
| R21 | 普通 `applySyncBatch` 遇到只带 `Read` 的 partial `Change`，可能用 nil 清空 `subject`/`sender`/`received_raw` | 服务器 `Change` 只带 `Read`；本地 upsert 后主题/发件人/日期变空 | 列表显示失真，且写路径若直接 apply 回包会放大 | 本批 `commit*` 排除目标 `added/changed` 保护写路径；普通同步统一 `COALESCE` 属 SCN-0003 语义变更，另立 CMP-STORE 任务，不混进本批 | `design/components/CMP-STORE/spec.md` 设计增量、`design/scenarios/mail/receive/inbox-sync/scenario.md`（仅登记，不本批改） |
| R22 | 非可选写端口使 T-1114-15/16 必须同一 change 改 `CMP-ROOT`，跨组件仅装配例外与组件级 WIP 冲突 | 两个 change 并行，或与其他 `CMP-ROOT` 任务并行；组合根被塞入业务判断 | 任务无法按单组件评审/回滚；组合根变成第二个业务层 | T-1114-10 已登记例外：组件列写 `+CMP-ROOT（仅装配）`，`CMP-ROOT` 的 WIP 由该 change 独占，不并行第二个 `CMP-ROOT` 任务；组合根只构造/注入/路由；P1 确认清单与决策记录同步 | `design/architecture.md` §3.1/§10、`design/components/CMP-ROOT/spec.md`、`plan/roadmap.md` §W-M3-03 |
| R23 | 搜索模式的列表/选择身份只按 `serverID`，跨文件夹可能重复 | `searchLocal` 跨文件夹返回；`messages` 主键含 `folder_id`；`Selection.messageID`/`ForEach(id: serverID)` 只按 `serverID` | 搜索模式下删除/打开可能命中另一文件夹的同 ID 邮件；`SCN-0009` 的搜索删除断言可能假绿 | T-1114-17 用跨文件夹同 `serverID` fixture 验证，作为验收前证据；若冲突，把列表/选择身份改为 `MessageRef`（folder + serverID）或等价复合键；若因此改 `Selection.messageID` 公开类型/语义，按 P2 契约变更另评，不在本批静默改；现有场景断言不足以覆盖冲突，若冲突成立按 P2 修订场景，不在本节点重写 | `design/components/CMP-PRES/spec.md` 设计增量、`design/components/CMP-APP/spec.md`、`design/scenarios/mail/read/keyboard-delete/scenario.md` |

## 风险等级口径

- 高：直接使项目不可用或造成合规事故（R1、R2、R11）。
- 中：影响关键旅程但可降级（R3、R4、R5、R6、R8、R12、R13、R16、R18、R19、R20、R21、R22、R23）。
- 低：局部体验或可回滚（R7、R9、R10、R15、R17）。

R14 已于 2026-11-14 关闭（T-1114-02：网关 Sync 信封实测返回 `Cc`）。
