---
layer: design
module: mail
status: designed
updated: 2026-11-13
flow: mail/read
scenario: SCN-0004
---

# SCN-0004 邮件阅读

**结果**：用户点开列表中的一封邮件，1 秒内看到信封与正文；正文尚未拉取时先出现占位，后台补拉完成后自动替换，不需要用户重新点开。

## 入口

- UI 读路径：`MailStore.messages(limit:)`、`MailStore.body(...)`（`page` / `messageDetail` 契约未实现）
- 补拉：`CMP-EAS#fetchBody` → `CMP-STORE#applySyncBatch`
- 渲染：HTMLSanitizer + WKWebView（architecture §2）

## 运行序

流程 `F-READ-01`：

1. 用户点击列表项 → 同步读 `CMP-STORE#messageDetail`，纯本地，不触网。
2. 有正文 → 经 sanitizer 后交 WKWebView；只有 Sync 摘要（前 500 字符纯文本）→ 先按 `pre-wrap` 渲染摘要并提示「正在获取完整正文」，同时投递补拉意图；两者都没有 → 渲染占位「正在获取正文」。
3. 补拉：`CMP-EAS#fetchBody`（先取 2 万字符 HTML，网关回 `Truncated=1` 则去掉上限再取一次；纯文本回退按纯文本渲染）→ 落库 → 替换摘要。补拉失败时摘要保留并提示「正文获取失败」，无摘要才转失败态。
4. 附件区按元数据渲染；点击转 `SCN-0005`。
5. 已读标志：本地即时置已读，异步回写服务器（失败不回滚 UI，仅记录待同步）。

失败路径：

- 补拉失败 → 有摘要时保留摘要 + 「正文获取失败，重试」；无摘要时占位改为失败态，保留重试入口；不阻塞跳到下一封；
- 网关仍截断 → 正文照常显示，另给「正文过长，只返回了前面一部分」提示，不静默丢内容；
- HTML 含脚本/远程资源 → sanitizer 移除脚本，远程图片默认阻止（architecture D5）；
- 邮件在补拉期间被服务器删除 → 丢弃补拉结果，列表标删除。

## 不可变引用

- 列表与正文分表；`messageDetail` 不得扫正文表做列表查询。
- HTML 渲染策略（D5）：关脚本、默认阻止远程资源。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0004-01` | 正 | 已有正文 → 点击到可见 < 1s（本地库热身，1 万封基线） |
| `T-SCN-0004-02` | 正 | 缺正文 → 先占位，补拉成功后自动替换，无需二次点击 |
| `T-SCN-0004-03` | 正 | 含 `<script>` 与远程 `<img>` 的正文 → 脚本不执行、图片不发请求 |
| `T-SCN-0004-04` | 反 | 补拉返回 503 → 占位显示重试态，列表可继续滚动与打开其它邮件 |

## 状态

`designed`（2026-11-13 核对）。运行序、引用、测试方案与入口齐；实现与验证如下。

实现：`fetchBody`（截断时去上限重取）、`MailStore.applyBody`、`MailboxModel` 先渲染摘要再补拉、`MessageBodyView`（WKWebView、禁 JS、CSP 阻止远程资源）已落地；2026-11-10 修掉「同步摘要冒充正文」（`b1ec332`）。**已读回写服务器未实现**，sanitizer 仍是 CSP + 关脚本的轻量实现。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0004-01` | 未测：真机可打开并渲染，但「1 万封、< 1s」P95 未测（只有 5k 基线） |
| `T-SCN-0004-02` | 通过（组件级）：`MailboxModelTests`「a missing body is fetched and becomes the detail state」「a sync preview does not stand in for the body, so the real fetch still runs」 |
| `T-SCN-0004-03` | 部分：CSP 禁脚本与远程资源阻止靠代码审查（`MessageBodyView`）；无「脚本不执行、图片不发请求」的自动化断言 |
| `T-SCN-0004-04` | 通过（组件级）：`MailboxModelTests`「a failed fetch keeps the preview readable instead of blanking the pane」 |

未转 `verified` 的原因：01 无性能证据、03 无自动化断言、已读回写未落地。
