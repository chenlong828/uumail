---
layer: plan
module: global
status: draft
updated: 2026-11-24
---

# 风险（现行）

只记仍未关闭的跨工序风险：触发信号、影响、缓解/待决、落点。单工序内部风险写在该工序 brief 里。

2026-11-24 复核 + 同日拍板：已完成处置的 32 条移入 `history/decisions/2026-11-24-risk-closeout.md`；
Q1–Q7 的拍板结论见 `history/decisions/2026-11-24-risk-review-decisions.md`。本文件只留仍存在或待执行的风险，
分「已拍板待执行 / 处置中 / 已接受或延后 / 外部监控 / 衍生风险」五组。

## 一、已拍板、待执行

| ID | 风险 | 拍板结论 | 后果与顺序 | 落点 |
|---|---|---|---|---|
| R21 | 普通同步遇到只带 `Read` 的 partial `Change`，会用空值覆盖 `subject`/`sender`/`received_raw` | **立即修**（D2）：三字段补 `COALESCE` + L1「只带 Read 的 Change 不清空信封」 | 先于 W-M3-17 实现；`MailStore.swift#applyDelta` 与 `MailStoreTests` 小改，不新增 schema | `MailStore.swift#applyDelta`、`MailStoreTests` |
| R45 | `CMP-STORE` 实测 **1225/1000**（2026-11-24 16:45，含新 `MailStore+Lookup.swift` 73；拆分前仍在长），`MailStore+Meetings.swift` 273 行（设计承诺 ≤120） | **先立 P1 拆分，不上调预算**（D1）：先拆 meetings，账号/文件夹另立 `W-REFACTOR-02` **已关闭（2026-11-24）**：`CMP-STORE` 现 **952/1000**，`meetings` 读写析出到 `CMP-MEETING-STORE`（287 行）。| 拆分后再开 W-M3-17；并行会话的「约 814/924」估算作废，拆分后重测；规格预算节要同步 拆分记录见 `plan/roadmap.md` §W-REFACTOR-03。| `CMP-STORE/spec.md` 预算节、`roadmap.md` §W-REFACTOR-02 |
| R70 | `CMP-PRES` `MailboxViewModel.swift` **424** 行（2026-11-24 16:45，新增 Reader 文件后主文件仍涨），超单文件 ≤400 | **拆文件**（D1）：Reader/列表窗口逻辑放新文件；不上调 450 **已关闭（2026-11-24）**：`MailboxViewModel` 现 **366/400**（列表加载与选中拆到 `MailboxViewModel+List.swift`，69 行）。| 并行会话已新增 `MailboxViewModel+Reader.swift`，需在主文件重测后再判断是否闭合 另 `CalendarViewModel` 424→172 + `CalendarProjection` 254。| `CMP-PRES/spec.md` 预算节、`T-1124-19` |
| R71 | `CMP-APP` `MailboxView.swift` 305 行、`CalendarView.swift` 325 行，均超单文件 ≤300 | **拆文件**（D1）：浮窗入口/手势放独立文件；不上调 320 | 与 W-M3-17 的新视图文件一起落，避免再往主文件加行 | `CMP-APP/spec.md` 预算节、`T-1124-20` |
| R72 | `Scenes` 合计 **1306/1200**（2026-11-24 16:45），且已有两个 HTML 纯工具（`HTMLText` 221 + `InlineImageHTML` 165） | **立 P1 拆分**（D1）：`HTMLText`/`InlineImageHTML` 到纯工具组件，预算不动 **已关闭（2026-11-24）**：`Scenes` 现 **923/1200**（`HTMLText`/`InlineImageHTML` 拆到 `CMP-HTML`，新 target `HTMLSupport`）。| 拆分触发条件已满足；不排在拆分前继续往 `Scenes` 加功能 `HTMLSupport` 391 行；`Scenes`/`Presentation` 各加一条 `import`。| `architecture.md` §7 第 12 条、`Scenes` 预算 |
| R13 | 发送只入队，列表/状态栏没有待发/失败计数 | **下一批做**（D7）：W-M3-17 后单独小批加 `pending`/`failed` 角标 | 本轮不塞进浮窗批次；在角标落地前保留撰写页文案 | `CMP-PRES/spec.md`、`CMP-APP/spec.md`、`CMP-OUT/spec.md` |
| R73 | 发布前证据未闭环：6 张核心场景卡仍 `designed`，多项 L3/真机冒烟未执行 | **发布前逐张补 `verified` + 人工冒烟清单**（D17） | 作为发布门，不是 W-M3-17 验收门；未完成不宣称「发布就绪」 | `roadmap.md`、各场景卡 §状态 |
| R77 | `MailDomain` **1503/800 目标**（`Meeting.swift` 682 + 其它 821，2026-11-24 `wc -l`） | 会议值类型 2026-11-24 P1 加入后未重估预算 | 平台契约组件继续增长，契约评审与装载成本上升 | **另立 P1 决定**：拆会议契约到独立组件，或经人工上调目标；本批只登记与实测，不静默调预算 | `CMP-DOMAIN/spec.md` 预算节、`plan/roadmap.md` |

## 二、处置中（W-M3-17，设计完成、待实现）

| ID | 风险 | 现状 | 影响 | 处置/拍板 | 落点 |
|---|---|---|---|---|---|
| R62 | 浮窗要按「文件夹 + serverID」取不在当前列表页的邮件，`ReadScene` 只有按文件夹取页 | 读契约已按 P1 确认（D12）；`MailStore`/`ReadScene` 新查询已在写 | 若实现期在视图层过滤，跨组件契约被绕过；更早邮件打不开 | `T-1124-17`/`T-1124-18` 落 `message(account:folder:serverID:)` 与 `messages(folderID:since:)`；不改 schema | `CMP-STORE`/`CMP-SCN-READ` 增量、`roadmap.md` §W-M3-17 |
| R64 | 浮窗就地撰写与主窗口撰写 sheet 各持一个 `ComposeViewModel`，可能两份草稿/引文错位/关窗丢稿 | 设计已定：撰写态禁替换、关闭走「放弃这封邮件？」、种子只从本窗取 | 用户丢草稿或发出不完整回复 | `T-SCN-0025-04` 反例钉住「取消/确认都不入队」 | `CMP-PRES` 增量、`SCN-0025` |
| R65 | 更早邀请正文未缓存时浮窗先占位再补拉；浮窗无远程图片开关，补拉失败只有占位 | 设计已定占位文案与可点重试 | 用户以为浮窗坏了 | `SCN-0024` 失败路径覆盖「来源邮件已删/未缓存」 | `CMP-APP` 增量、`SCN-0024` |
| R66 | 浮窗阅读态默认放行远程资源（D6），追踪像素可得知打开时间与 IP；同封在浮窗有图、主窗口仍是占位 | **确认维持默认显示**（D3） | 隐私泄露；两窗口表现不一致为已知代价 | 放行只限浮窗阅读态；顶部静态提示；主窗口与撰写编辑器仍阻止；不扩 ATS；被否决才回退并重开 D6 | `history/decisions/2026-11-24-floating-reader-window.md` D6、`SCN-0025` |
| R67 | 列表改「最近 30 天、不封顶」（D12）后，大邮箱首屏读取/渲染变重，可能突破 5k 基线 | **突破就回设计**（D4）；5k 夹具随 `T-1124-21` 跑 | M4 性能门槛失守；`SCN-0026` 假绿 | 查询按 `received` 时间窗、不在客户端过滤；>1s 停下评估分页/封顶，不静默放宽、不改回 200 | `REQ-0033`、`SCN-0026`、R6 |
| R68 | 日历去掉详情后，单击/双击/Enter/空格共用一块区域，可能互相吃掉 | 探针证 `clickCount=1,2` 会先发单击再发双击；并行会话已按「立即选中」把本行标成关闭 **已实现（2026-11-24）**：`ClickCatcherView` 单次单击延迟 0.28s 判定，双击取消待生效选中；探针 `evidence/calendar-click/calendar-click.txt`（立即 0 → 延迟后 1；1,2 → 选中 0/打开 1）。| 双击打开前会闪一下选中；与用户拍板不一致 | **已拍板延迟 250–300ms 判定**（D5）：单击延迟生效、双击直接打开；若实现成本过高，回设计重开 D9，不静默沿用「闪一下」 | `CMP-APP` 增量、`SCN-0024` |

R63（窗口载体）已由 2026-11-24 探针关闭并移入 `history/decisions/2026-11-24-risk-closeout.md`：
SwiftUI `Window` 显示前不能可靠应用计算尺寸，改用 AppKit `NSWindow` + `NSHostingController`。

## 三、已接受 / 延后（保留监控）

| ID | 风险 | 口径与复核条件 | 落点 |
|---|---|---|---|
| R4 | GAL 与联系人不可用 | 首版只做本机通讯录 + 收件人历史；要 GAL 另立需求 | `CMP-EAS/playbook.md` §5 |
| R5 | 只支持 5 分钟轮询，新邮件有延迟 | 网关不支持 Ping 长轮询；固定 5 分钟并在 UI 标注；要 ≤60s 需换通道 | `CMP-EAS/playbook.md` §5.2 |
| R7 | HTML 邮件攻击面 | 已设控制：WKWebView 关脚本 + CSP + 默认阻止远程 + sanitizer；改 CSP/载体时回归 | `architecture.md` T5、`SCN-0004` |
| R8 | 服务器限流 | 已设控制：单账号串行、退避、`Retry-After` 优先；出现 503 风暴时复核 | `CMP-SYNC/spec.md` |
| R9 | WBXML 编解码边界 | 已设控制：golden fixture round-trip、以探针真实字节为准 | `CMP-EAS/playbook.md` §4 |
| R10 | 时间与排序错乱 | 已设控制：服务器 `DateReceived` 排序，本地时间兜底 | `CMP-STORE/spec.md` |
| R12 | 无 certificate pinning；库/缓存明文、无 SQLCipher、无审计日志 | 凭据只进 Keychain，库/缓存依赖 FileVault；不做 pinning/SQLCipher 为已知接受项 | `CMP-STORE/spec.md`、`CMP-APP/spec.md` |
| R25 | `UserDefaults` 写失败没有可观察同步信号 | 接受测试强度不足：靠「不抛/不回滚 + 会话状态真源」保证；要强制注入另评存储协议 | `CMP-PRES/spec.md`、`SCN-0011` |
| R30 | 发起人期望的「发送时间」是真实 `Sent`，不是 `DateReceived` | `REQ-0017` 已写明非目标；要 `Sent` 另立需求并先证网关可达性 | `REQ-0017`、`SCN-0012` |
| R31 | L2 探针依赖 SwiftUI「可选 `Text` 由 `NSTextField` 承载」 | OS/SwiftUI 升级后探针可能全红；探针先断言字段存在再比对，红了再换 seam，不静默假绿 | `SCN-0012`、`task-spaces/20261116-212545/evidence/header-probe/` |
| R37 | L2 工具栏探针依赖 `sendEvent` 合成点击 | 升级后可能点不中；点击不动即红灯，不静默跳过；必要时改直接触发 `Actions` 并登记限制 | `SCN-0013`/`SCN-0014`、`task-spaces/20261116-223645/evidence/toolbar-probe/` |
| R46 | 收件人联想是会话内投影，旧邮件/未同步文件夹/超上限联系人不出现 | `REQ-0022` 非目标与 `SCN-0017` 失败路径已写明；要持久联系人另立 v11 需求 | `REQ-0022`、`SCN-0017`、`history/decisions/2026-11-18-recipient-autocomplete.md` |
| R49 | 首次聚焦聚合 5,000 封信封可能阻塞主线程，且没有实测 | **2026-11-24 拍板延后**（D16），不排下一批；保留「目标 ≤100ms、无 5k 夹具」的事实 | `CMP-PRES/spec.md`、`SCN-0017` |
| R53 | ATS 载体契约没有 CI 回归守护 | **2026-11-24 拍板延后**（D16）；继续靠里程碑/发布前手动复跑 | `SCN-0018`、`Scripts/` |
| R54 | 像素/解压炸弹 guard 未实现 | **2026-11-24 拍板延后**（D16）；`InlineImageHTML` 仍只有 20MB 字节截断 | `SCN-0019`、`InlineImageHTML` |
| R55 | HTML 注释/其它属性值内嵌套的 `<img src=…>` 仍会被扫描/改写 | **2026-11-24 拍板延后**（D16）；可见正文不变，但会多一次本地下载 | `task-spaces/20261120-111818/review4.md` §6 N1、`SCN-0019` |
| R56 | 重复会议按时区固定偏移展开，跨 DST 偏一小时 | **2026-11-24 拍板维持固定偏移**（D12/Q5）；事件详情标注；要精确另立 P2 | `CMP-DOMAIN/spec.md`、`SCN-0024` |
| R58 | 不回填历史邀请，升级后日历为空、旧邀请无会议卡 | 用户 2026-11-24 二次确认接受；空态写明「只展示升级后新收到的邀请」 | `REQ-0029`、`SCN-0024` |
| R59 | 月/周网格与会议卡的 L2 探针读不到文本/几何，只能降级 L1 | 两条视觉/`NSWorkspace` 断言已按场景卡登记为发布前人工冒烟，不放宽为 L1 通过 | `SCN-0023`/`SCN-0024` |
| R60 | 网关返回「请求类邮件但缺 `MeetingRequest` 子树」时，日历页为空 | **2026-11-24 拍板延后**（D16）；缺该用例的事实保留，不写成已覆盖 | `EASClientTests`、`SCN-0024` |
| R61 | 启用 WAL 后 `-wal`/`-shm` 副文件，备份/复制漏带导致数据不一致 | **2026-11-24 拍板延后**（D16）；仍只有文字约定，不做 `VACUUM INTO` 命令 | `CMP-STORE/spec.md` WAL 增量 |
| R69 | 打开浮窗即标已读（D7）不可撤销 | **2026-11-24 拍板接受**（D15）；要撤销另立「标为未读」需求 | `REQ-0031`、`SCN-0025`、决策 D7 |

## 四、外部监控（项目不可控，只跟信号）

| ID | 风险 | 触发信号 | 项目侧动作 | 落点 |
|---|---|---|---|---|
| R1 | 网关设备清单被清理或换机 | 所有命令 `200` 空 body、写命令 `401`、短信回执显示设备被删 | 已把「0 字节 200」映射为 `deviceNotRegistered` 并给登记指引；启动做轻量探活 | `CMP-EAS/playbook.md` §6 |
| R2 | 公司收紧 EAS 或要求 MDM/零信任客户端 | IT 公告、网关拒绝新设备、`OPTIONS` 不再返回命令列表 | 只走官方移动端通道，不绕过认证；上线前与 IT 确认合规；失败明确提示 | `architecture.md` §7 |
| R3 | 公司迁移到 Exchange Online / 关闭本地 EAS | IT 公告、账号迁云、本地网关下线 | 项目定位即私有化 Exchange 客户端（T13），不做假兼容；迁移即重新立项 | `history/decisions/2026-11-09-scope-baseline.md`、`architecture.md` T13 |
| R11 | 抓包样本含敏感内容 | 真实邮件正文/主题进入仓库或日志 | 脱敏后入仓；`.env`/`logs/`/`output/` 不入库；提交前检查 | `history/decisions/2026-11-09-scope-baseline.md`、`architecture.md` §7.3 |

## 五、本次拍板带入的衍生风险（待设计）

| ID | 风险 | 触发 | 影响 | 控制方向 |
|---|---|---|---|---|
| R74 | 同步日历集合后，邀请与日历项按 `UID` 去重/改期/取消的冲突规则未定 | 同一会议既有邀请又有日历项；组织者改期；取消 | 重复条目、旧时间、已取消会议仍显示 | Q6 设计时先定「服务器日历优先 + 邀请补历史」的合并表；用真实样本钉住 |
| R75 | `PendingOps` 离线队列与在线写回并存，顺序/重复写/跨设备一致未定 | 断网删除后恢复网络；同一封在别的设备已改 | 重复删除、已读回退、队列卡死 | M4 P1 设计：单账号 FIFO、幂等键、冲突以服务器为准；先补离线用例 |
| R76 | 3 个月删邮件行会破坏搜索/日历/附件/选中态的引用完整性 | 定期清理与用户正在浏览/日历引用旧邮件同时发生 | 日历空白、附件打不开、列表选中悬空 | 清理契约先设计级联与保留策略；删除前检查会议/附件引用；补清理用例 |

## 风险等级口径

- 高：直接使项目不可用或造成合规事故（R1、R2、R11）。
- 中：影响关键旅程但可降级（R3、R4、R5、R8、R12、R13、R21、R45、R49、R53、R54、R56、R58、R59、R60、R61、R62、R64、R66、R67、R68、R70、R71、R72、R73、R74、R75、R76）。
- 低：局部体验或可回滚（R7、R9、R10、R25、R30、R31、R37、R46、R55、R65、R69）。

## 变更记录

- 2026-11-24（W-REFACTOR-03 预算拆分）：R45 关闭（`CMP-STORE` 952/1000，`meetings` → `CMP-MEETING-STORE`）；R70 关闭（`MailboxViewModel` 366/400、`CalendarViewModel` 172）；R72 关闭（`Scenes` 923/1200，`HTMLText`/`InlineImageHTML` → `CMP-HTML`）；`CMP-EAS` 1513→1150/1500（`WBXML` → `CMP-WBXML`，363 行）；`CMP-APP` 各文件 ≤300（实测最大 293）；新增 R77（`MailDomain` 1503/800 目标，待 P1 决定）。
- 2026-11-24（风险拍板）：Q1–Q7 与 R13/R21/R45/R49/R53/R54/R55/R60/R61/R66/R67/R68/R69/R70–R73 逐项拍板，
  结论见 `history/decisions/2026-11-24-risk-review-decisions.md`；新增 R74–R76（日历集合冲突、离线队列、3 个月删行）。
  R21、R45、R70–R72 转为「已拍板待执行」；R49/R53/R54/R55/R60/R61 延后；R68 由「探针关闭」改回「处置中：延迟判定」。
- 2026-11-24（W-M3-17 设计，`T-1124-16`）：R62 的 P1 确认门通过（决策 D12）；R63 由窗口探针关闭；
  R64/R65/R66/R67/R69 分别落 `SCN-0025` 反例、`SCN-0024` 失败路径、决策 D6 可逆边界、`SCN-0026` 的 5k 断言、已接受限制。
- 2026-11-24（全量复核）：R14–R63 中已完成处置的 32 条移入 `history/decisions/2026-11-24-risk-closeout.md`；
  新增 R70–R73（PRES/APP/Scenes 预算漂移、发布前证据未闭环）；R21 经代码复核确认未关闭；
  R45 更新为实测 1152/1000（拍板时已涨到 1225）；R60 的「已覆盖」更正为「缺用例」；R62 由「待 P1 确认」改为「已确认待实现」。
