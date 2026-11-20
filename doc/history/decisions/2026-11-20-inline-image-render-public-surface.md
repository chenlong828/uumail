---
layer: history
module: mail
status: frozen
updated: 2026-11-20
---

# 内联图片设计：P2 additive 公开面人工确认（2026-11-20，第 2 轮）

## 背景

`REQ-0025` / `SCN-0019` 的第 1 轮设计（`task-spaces/20261120-111818/design.md`）在 `Scenes` 新增
`ReadScene.renderInlineImages(for:html:)`、在 `Presentation` 新增 `MailboxViewModel.inlineImageHTML`（均为
additive public，跨 `Scenes`/`Presentation`/`uumail`），并把它们记为 **P2 默认确认（未经人工）**。原决策记录
`doc/history/decisions/2026-11-20-inline-image-render.md` 已 `frozen`。设计评审（`review.md`）判 fail：

- B1：`auto-confirm` §2 的默认确认不覆盖公共契约/跨模块接口；§3.1 要求人工确认；项目先例
  `2026-11-16-remote-toolbar-mark-read.md` 对同类 P2 additive public 成员设人工门，缺记录时实现准出 fail。
- B2：`SCN-0019` 结果段「不整页空白」与失败路径「纯图片外部失败仍空白」冲突，用户样本正是纯图片。

设计回退第 2 轮按 `auto-confirm` §3 用 `mcp__agentflow__confirm` 就公开面提**一个问题**，选项为
A 批准两个公开面 / B 仅批准 VM 状态 / C 零新增公开面 / D 判 P1。人工选择 **A**。B2 由设计按评审要求
统一口径，另见 `SCN-0019`、`REQ-0025` D8 与 `design2.md` §4.7。

## 确认来源与范围

- **确认人**：任务发起人（工作区所有者）。
- **时间**：2026-11-20。
- **方式**：本次运行（`task-spaces/20261120-111818`，方案设计回退第 2 轮）的 `mcp__agentflow__confirm`
  （`confirmation_request`）；运行注入 `[人工确认]`，决定 **pass**。
- **问题**：是否批准 REQ-0025 的 P2 additive 公开面：`ReadScene.renderInlineImages(for:html:)` 与
  `MailboxViewModel.inlineImageHTML`？
- **人的意见**：**A 批准两个公开面（推荐）：保留 Scenes 规则+PRES 投影分工，最小改动**。
- **确认项**：
  1. `Scenes.ReadScene` 新增 `public func renderInlineImages(for ref: MessageRef, html: String) async -> String?`；
  2. `Presentation.MailboxViewModel` 新增 `public private(set) var inlineImageHTML: String?`（只读）；
  3. 两项均按 **P2 additive** 处理，保留既有 `Scenes`（`cid:` 规则 + 取负载）与 `Presentation`（渲染投影）
     分工。
- **未确认、仍为默认确认（未经人工）**：D1–D8（场景归属、匹配族、载体族、取负载时机、附件条、失败口径、
  资源 guard、不改 CSP/`baseURL`/JS/scheme/schema/`MailDomain` 公开契约）。本次人工确认只关闭公开面门，
  不是对整份设计的逐项签字，也不把 D1–D8 写成人工确认。
- **记录方式**：本记录由设计节点按人工答复落盘，**不代签**、不伪造第三方签字；原始答复以上述运行注入的
  `[人工确认]` 为准。

## 决定

| # | 项 | 结论 |
|---|---|---|
| C1 | `ReadScene.renderInlineImages(for:html:)` | **批准**新增（additive public）。只取当前正文实际引用的内联附件，复用既有 `downloadAttachment`/`AttachmentFiles` 缓存/单飞；单张失败/超限/取消跳过，不抛错；不改 `open`/`downloadAttachment` 语义。 |
| C2 | `MailboxViewModel.inlineImageHTML` | **批准**新增（additive public，只读）。只是当前正文的渲染投影；`body`/`quotableHTML`/`message_bodies` 保持原始 HTML，data URL 不持久化、不进回复引用。 |
| C3 | 定级 | **P2**（跨 `Scenes`/`Presentation`/`uumail` 三层；两个 additive public 面 + internal `InlineImageHTML`；无核心 schema/数据所有权/`MailDomain` 契约/热路径依赖变更）。评审已认可 P2；不升 P1。 |
| C4 | 组件分工 | 保留 **Scenes 规则 + PRES 投影**：`cid:` 提取/匹配/嗅探/改写与取负载在 `Scenes`；`Presentation` 只持渲染投影与任务生命周期；`uumail` 只换显示串。`InlineImageHTML` 仍 internal。 |
| C5 | task-split 门 | 公开面确认门**已关闭**，可进入 task-split/实现；task-split 仍须引用本记录，并把 `Scenes` 预算上限/拆分触发（`design2.md` §2 N1）与确认范围写进任务表。 |
| C6 | 状态位 | 本记录不翻转任何状态：`SCN-0019` 保持 `designed`、`REQ-0025` 保持 `accepted`；实现/验证/收尾按 `af-flow-rule` §7。 |

**与原记录的关系**：本文件是 `2026-11-20-inline-image-render.md` 的 **addendum**，不覆盖、不改写原 `frozen` 记录。
原记录中 D1–D8 的默认确认继续有效（未经人工）；本 addendum 只补充/取代「两个 additive public 面是否需要
人工确认、确认结果为何」这一部分，并作为 B1 的关闭证据。

## 影响

- **设计产物**：`task-spaces/20261120-111818/design2.md` §4.6/§8 D9；`SCN-0019` §状态；`REQ-0025` 澄清 D8。
- **项目文档**：`doc/design/architecture.md` §10.3（P2 默认确认改为公开面人工确认）、§4 冷路径表（取消语义）、
  §10.2 残留（预算/像素 guard）；`CMP-SCN-READ`/`CMP-PRES`/`CMP-APP` 增量的定级/确认行引用本记录。
- **实现**：尚未改任何 `Sources/`/`Tests/`；本次为设计/文档变更。
- **排期**：task-split 建任务表时引用本记录；不新增 schema/迁移/依赖/target。
- **回退**：撤销两个 public 成员及其接线即可；纯 additive、无数据迁移；`body`、附件条、远程开关、CSP、
  `baseURL` 均不受影响。若后续要扩大到第三个 public 成员或改 `MailDomain`/schema，另走 `auto-confirm` §3。

## 未采纳 / 明确不做

- **不采纳 B（仅批准 VM 状态）**：会让 `Presentation` 直接读文件/解析 HTML，改动既有边界，且仍需一个 public 成员；
  收益小于代价。
- **不采纳 C（零新增公开面）**：`uumail` 不能 import `Scenes`，把改写下沉到 UI 会造成分层退化；且与已通过的
  `Scenes` 规则归属冲突。
- **不采纳 D（判 P1）**：`ReadScene` 不是平台级核心契约，未触核心 schema/数据所有权/热路径依赖；评审已认可 P2。
- **不做**：新增 `attachments.content_id`/`Attachment.contentID`、改 EAS 命令、改 CSP/`baseURL`/scheme、注册
  `WKURLSchemeHandler`、改远程开关、隐藏附件条、把 data URL 写进 `message_bodies`/`body`/回复引用。

## 落点

- 设计：`task-spaces/20261120-111818/design.md`（第 1 轮，保留）、`task-spaces/20261120-111818/design2.md`（第 2 轮：§1 B1、§4.6、§8 D9）。
- 场景/需求：`doc/design/scenarios/mail/read/inline-image-render/scenario.md`（`SCN-0019`，`designed`）、
  `doc/requirements/REQ-0025-inline-image-render.md`（`accepted`，D8 澄清）。
- 规格/架构：`doc/design/components/CMP-SCN-READ/spec.md`、`CMP-PRES/spec.md`、`CMP-APP/spec.md` 的 2026-11-20 增量；
  `doc/design/architecture.md` §4、§10.2、§10.3。
- 后续：task-split 任务表引用本记录；实现后由实施/验证节点补进度行，不翻转 `SCN-0019`/`REQ-0025` 状态位。
