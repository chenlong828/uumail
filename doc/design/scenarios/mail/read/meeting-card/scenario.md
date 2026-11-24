---
layer: design
module: mail
status: designed
updated: 2026-11-24
flow: mail/read
scenario: SCN-0023
---

# SCN-0023 阅读页会议邀请卡

**结果**：用户打开一封会议邀请邮件，信封头下方出现会议卡，显示时间、地点、组织者与重复说明；点「在日历中打开」把这场会议（重复会议为整个系列）交给系统默认日历应用导入。非邀请邮件不出现卡片；正文、信封头与附件条保持现状。

## 入口

- `CMP-PRES#MailboxViewModel.meetingCard`（由选中 `Message.meeting` 生成展示值）
- `CMP-APP#MeetingCardView`（卡片渲染与「在日历中打开」入口）
- `CMP-SCN-CALENDAR#ics(uid:)`（按 `meetings` 行生成 iCalendar 文本）
- `CMP-DOMAIN#MeetingInvite.ics(...)`（纯序列化，含重复规则）

## 运行序

流程 `F-READ-10`：

1. 用户选中一封邮件；`MailboxViewModel.headerPresentation` 与正文流程不变。
2. `MailboxViewModel.meetingCard`：`selectedMessage.meeting` 为 `nil` → 返回 `nil`（视图不渲染卡片、不占位）；非 `nil` → 生成 `MeetingCardPresentation`：`时间`（本机时区；全天显示「全天」）、`地点`（缺失时省略该行）、`组织者`、`重复说明`（「每周一」「每 2 周」「共 N 次」「至 2027-01-01」按可判定部分拼接，不确定时不编造）。
3. `MeetingCardView` 渲染在信封头与正文之间，位于正文状态 switch 之外（与信封头同一层），`loading`/`loaded`/`failed` 都可见。
4. 点「在日历中打开」→ `CalendarScene.ics(uid:)`：从 `MailStore` 读该 UID 的会议行 → `MeetingInvite.ics` 生成文本（`BEGIN:VCALENDAR`/`VERSION:2.0`/`PRODID`/`METHOD:PUBLISH`/一个 `VEVENT`；重复会议带 `RRULE`，全天带 `DTSTART;VALUE=DATE`）。
5. 视图层把文本写到 `FileManager.default.temporaryDirectory/<uid>.ics`，调 `NSWorkspace.shared.open(url)`；系统默认日历应用接收并导入。
6. 导入后清理临时文件（延迟删除或下次覆盖同名文件）；失败路径见下。

失败路径：

- 生成失败（会议行已被入库的更新删掉、`UID` 缺失）→ 卡片内联中文错误「无法生成日历文件」，可再次点击重试；不弹窗、不崩。
- `NSWorkspace.open` 返回 `false` 或抛错 → 卡片内联「没有可用的日历应用」，不清空卡片。
- 时区偏移缺失/畸形 → 按 UTC 时间生成，卡片与 `.ics` 都用同一时间，不出现卡片与导出不一致。
- 重复规则无法解析 → 导出单次事件，并在卡片标注「重复规则无法完整展开」。

## 不可变引用

- `SCN-0012`：阅读页信封头的字段、行数与布局；本卡只在信封头之下新增一块，不改信封头本身。
- `SCN-0004`：正文补拉、缓存优先、截断提示与 CSP；卡片不参与正文渲染。
- `SCN-0019`/`SCN-0020`：内联图片与附件条；卡片不动附件条。
- 阅读路径零网络：卡片数据来自 `MailStore`，点「在日历中打开」也不触网。
- 不新增第三方依赖、不新增 target、不改 schema（复用 `REQ-0029` 的 `meetings`）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0023-01` | 正 | 打开样本邀请（2026-11-19 09:30–12:00、C4519、王权英）→ 卡片显示「11月19日 09:30–12:00」「C4519」「王权英」；重复样本显示「每周一」 |
| `T-SCN-0023-02` | 正 | 打开非邀请邮件（普通正文）→ 无卡片节点；信封头与正文与改造前一致（回归 `SCN-0012`/`SCN-0004` 断言不退化） |
| `T-SCN-0023-03` | 正 | 点「在日历中打开」→ 生成文本含 `BEGIN:VEVENT`、`DTSTART`、`DTEND`、`SUMMARY`、`LOCATION`、`UID`；重复会议含 `RRULE:FREQ=WEEKLY`；`NSWorkspace` 替身被调用 1 次且 URL 存在 |
| `T-SCN-0023-04` | 反 | `TimeZone` 缺失且 `StartTime` 合法 → 卡片仍显示 UTC 换算后的本机时间，导出 `.ics` 成功且与卡片一致；`StartTime` 缺失 → 卡片不显示时间行但其余字段可用，不崩 |

## 状态

`designed`（2026-11-24 设计落卡；实现待 P1 确认门 `T-1124-02`）。

- 测试载体：`T-SCN-0023-01/02/04` 走 L1（`MeetingCardPresentationTests` + `MeetingICS` 纯函数用例）；`T-SCN-0023-03` 的「点击 → 生成 → 调用 opener」走 L2 视图探针（卡片按钮可触发、opener 用注入替身），失败按 `plan/risks.md` R41 处理。
