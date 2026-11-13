---
layer: design
module: mail
status: designed
updated: 2026-11-14
flow: mail/read
scenario: SCN-0004
---

# SCN-0004 邮件阅读

**结果**：用户点开列表中的一封邮件，1 秒内看到信封与正文；正文尚未拉取时先出现占位，后台补拉完成后自动替换，不需要用户重新点开。

## 入口

- `CMP-SCN-READ#bodyIfCached`、`#open`（`design/components/CMP-SCN-READ/spec.md`）
- `CMP-PRES#MailboxViewModel.openSelected`（`design/components/CMP-PRES/spec.md`）
- `CMP-DOMAIN#MailGateway.fetchBody`（经 `CMP-EASADAPTER`，返回 `FetchedBody`）
- `CMP-STORE#applyBody`、`#body`
- 渲染：`MessageBodyView`（WKWebView、禁 JS、CSP 阻止远程资源）

## 运行序

流程 `F-READ-01`：

1. 用户点击列表项 → 同步读本地列表与 `bodyIfCached`，纯本地，不触网（VM 状态 `.none`/`.loading`/`.loaded`）。
2. 命中缓存 → `BodyPresentation.loaded(html:truncated:)`，不发网络。
3. 未命中但有 Sync 摘要 → 先以 `BodyNotice.fetchingFullBody` 展示摘要（`pre-wrap`），同时 `ReadScene.open` 补拉。
4. 补拉：`fetchBody` → 纯文本转 HTML（`HTMLText`）→ `applyBody` → yield `.loaded`；`isTruncated` 透传到 `BodyPresentation.loaded(truncated:)`，UI 给「正文过长」提示。
5. 补拉失败 → yield `.failed(MailError)`；有摘要则 `BodyNotice.previewFallback` 保留摘要，无摘要则 `.failed(text)` 显示重试入口。
6. 附件区按元数据渲染；点击转 `SCN-0005`。
7. 已读标志：**未实现**（本地即时置已读、异步回写服务器都不存在）。

失败路径：

- 补拉失败 → 保留摘要或占位，提供重试；不阻塞跳到下一封；
- 网关仍截断 → 正文照常显示并提示「只返回了前面一部分」，不静默丢内容；
- HTML 含脚本/远程资源 → 关 JS + CSP 阻止（T5）；远程图片不发请求靠 CSP，无自动化断言；
- 邮件在补拉期间被服务器删除 → 未实现丢弃规则。

## 不可变引用

- 列表与正文分表；列表查询不扫正文表。
- HTML 渲染策略（T5）：关脚本、默认阻止远程资源。
- `FetchedBody` 的 `isHTML/isTruncated` 语义（D10，`history/decisions/2026-11-13-fetched-body-contract.md`）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0004-01` | 正 | 已有正文 → 点击到可见 < 1s（本地库热身，1 万封基线） |
| `T-SCN-0004-02` | 正 | 缺正文 → 先占位，补拉成功后自动替换，无需二次点击 |
| `T-SCN-0004-03` | 正 | 含 `<script>` 与远程 `<img>` 的正文 → 脚本不执行、图片不发请求 |
| `T-SCN-0004-04` | 反 | 补拉返回 503 → 占位显示重试态，列表可继续滚动与打开其它邮件 |

## 状态

`designed`（2026-11-14 核对）。入口已从旧 `MailboxModel` 改为 `ReadScene` + `MailboxViewModel`；测试证据更新如下。

实现：`ReadScene.open`（缓存优先、单飞、先 `applyBody` 再 yield）、`MailboxViewModel` 正文状态机、`MessageBodyView`（WKWebView、禁 JS、CSP）已落地。2026-11-10 修掉「同步摘要冒充正文」（`b1ec332`）。**已读回写服务器未实现**，sanitizer 仍是 CSP + 关脚本的轻量实现。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0004-01` | 未测：真机可打开并渲染，但「1 万封、< 1s」P95 未测（只有 5k 基线 `PerformanceTests`） |
| `T-SCN-0004-02` | 通过（组件级）：`ScenesTests`「a missing body is fetched once, stored as HTML, then yielded as loaded」；`PresentationTests`「a missing body is fetched and becomes the loaded state」 |
| `T-SCN-0004-03` | 部分：CSP 禁脚本与远程资源阻止只靠代码审查（`MessageBodyView`）；无「脚本不执行、图片不发请求」的自动化断言 |
| `T-SCN-0004-04` | 通过（组件级）：`ScenesTests`「a gateway failure is yielded as failed and does not overwrite the cache」；`PresentationTests`「a failed fetch without a preview becomes the retry state」「a failed fetch keeps the preview readable and allows retry」 |

未转 `verified` 的原因：01 无性能证据、03 无自动化断言、已读回写未落地。
