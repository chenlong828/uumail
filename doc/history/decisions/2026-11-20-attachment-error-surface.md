---
layer: history
module: mail
status: frozen
updated: 2026-11-20
---

# 附件取用设计：P2 additive 公开面人工确认（2026-11-20）

## 背景

`REQ-0026` / `SCN-0020`（附件取用交互：双击打开、右键另存为）的设计需要在 `Presentation` 的
`MailboxViewModel` 上新增一个只读错误状态：现有 `download` 用 `try?` 吞掉错误、只返回 `URL?`，
附件下载/另存为失败对用户完全静默；`REQ-0026` 要求失败可见、可重试，并复用 `ErrorText` 的唯一
`MailError → 中文` 映射。`Presentation` 是独立 target，因此 VM 错误状态必然是 public 面。

设计（`task-spaces/20261120-160446/design.md` §5）按 `auto-confirm` §3 用
`mcp__agentflow__confirm` 就公开面提**一个问题**；人工选择 **A**。

## 确认来源与范围

- **确认人**：任务发起人（工作区所有者）。
- **时间**：2026-11-20。
- **方式**：本次运行（`task-spaces/20261120-160446`，方案设计第 1 轮）的 `mcp__agentflow__confirm`
  （`confirmation_request`）；运行注入 `[人工确认]`，决定 **pass**。
- **问题**：REQ-0026 是否批准 `MailboxViewModel` 新增只读 `attachmentErrorText`（P2 additive public）？
- **人的意见**：**A 批准：新增只读 `attachmentErrorText`，`download` 签名不变，下载错误文案归 VM（推荐）**。
- **确认项**：
  1. `Presentation.MailboxViewModel` 新增 `public internal(set) var attachmentErrorText: String?`
     （公开只读；内部 setter 供同 target 的 `MailboxViewModel+Attachments.swift` 写入）。
  2. `download(_:)` 保持 `async -> URL?` 签名；失败时返回 nil 并写 `attachmentErrorText`；
     成功/切换邮件/清空选择时归 nil。
  3. 文案只经 `ErrorText` 映射；不新增强制中文拼接，不 switch 错误类型到视图。
- **未确认、仍为默认确认（未经人工）**：D1–D11（新建 `SCN-0020`、单击只选中、双击/Return 打开、
  右键最小菜单、APP 层保存面板与原子替换、缓存/prune 不改、失败 banner/错误落点、动作单飞、
  L1/L2 测试面、不改 schema/依赖、`SCN-0019` 只回归）。本次人工确认只关闭公开面门，不是对整份
  设计的逐项签字。
- **记录方式**：本记录由设计节点按人工答复落盘，**不代签**、不伪造第三方签字；原始答复以上述运行
  注入的 `[人工确认]` 为准。

## 决定

| # | 项 | 结论 |
|---|---|---|
| C1 | `MailboxViewModel.attachmentErrorText` | **批准**新增（additive public，公开只读、内部可写）。只承载附件下载失败的 `ErrorText` 文案；另存为失败由 APP 层 `saveErrorText` 承载，不混入。 |
| C2 | `download(_:)` | **签名不变**（`async -> URL?`）；失败返回 nil 并写文案；成功清空；不改成 throwing，不改调用点。 |
| C3 | 定级 | **P2**（跨 `Presentation`/`uumail`；一个 additive public 成员 + APP 层内部保存/交互文件；无核心 schema、数据所有权、`MailDomain` 契约、热路径依赖变更）。不升 P1。 |
| C4 | 不改面 | `MailDomain.Attachment`/`AttachmentFiles`/`MailGateway`、`attachments` schema、`Scenes`、`Composition`、`Package.swift`、target、第三方依赖均不变。 |
| C5 | task-split 门 | 公开面确认门**已关闭**，可进入 task-split/实现；task-split 仍须引用本记录，并写清文件/行数预算与 L1/L2 验证面。 |
| C6 | 状态位 | 本记录不翻转任何状态：`SCN-0020`/`SCN-0005` 保持 `designed`、`REQ-0026` 保持 `accepted`；实现/验证/收尾按 `af-flow-rule` §7。 |

## 未采纳 / 明确不做

- **不采纳 B（改 `download` 为 throwing）**：会破坏现有签名与调用点/测试，收益只是少一个只读成员；
  与既有 `deleteErrorText`/`markReadErrorText` 的「VM 持错误文案」模式不一致。
- **不采纳 C（零公开面）**：只能显示通用「附件下载失败」，丢失 offline/storage 等 `ErrorText`
  既有区分；用户价值低于一个只读成员的代价。
- **不采纳 D（不批准/回退）**：错误静默是 `REQ-0026` 明确要修的缺口；无替代机制能在不改公开面的
  前提下复用 `ErrorText`。
- **不做**：新增 `MailDomain`/`Scenes` public 成员、改 schema、加 `AttachmentExporting` 端口、
  把 `NSSavePanel` 放进 `Composition`、改缓存算法、补 25MB/续传/名称回退。

## 影响

- **设计产物**：`task-spaces/20261120-160446/design.md` §4.2/§5/§8；`SCN-0020`；`SCN-0005` 边界；
  `CMP-APP`/`CMP-PRES` 增量；`REQ-0026` 设计裁定。
- **实现**：尚未改任何 `Sources/`/`Tests/`；本记录为设计/文档变更。实现时只新增一个 public 只读
  属性 + `MailboxViewModel+Attachments.swift` 的下载错误写入；不新增其他 public 成员。
- **排期**：task-split 建任务表时引用本记录；不新增 schema/迁移/依赖/target。
- **回退**：删除 `attachmentErrorText` 与 `download` 内的写入/清空、APP 层改回通用失败文案；纯
  additive、无数据迁移；`download` 返回语义不变。若后续要扩大公开面（例如另存为也进 VM），另走
  `auto-confirm` §3。
