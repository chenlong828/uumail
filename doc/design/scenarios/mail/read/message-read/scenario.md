---
layer: design
module: mail
status: draft
updated: 2026-11-09
flow: mail/read
scenario: SCN-0004
---

# SCN-0004 邮件阅读

**结果**：用户点开列表中的一封邮件，1 秒内看到信封与正文；正文尚未拉取时先出现占位，后台补拉完成后自动替换，不需要用户重新点开。

## 入口

- UI 读路径：`CMP-STORE#page`、`#messageDetail`
- 补拉：`CMP-EAS#fetchBody` → `CMP-STORE#applySyncBatch`
- 渲染：HTMLSanitizer + WKWebView（architecture §2）

## 运行序

流程 `F-READ-01`：

1. 用户点击列表项 → 同步读 `CMP-STORE#messageDetail`，纯本地，不触网。
2. 有正文 → 经 sanitizer 后交 WKWebView；无正文 → 渲染占位「正在获取正文」，同时投递补拉意图。
3. 补拉：`CMP-EAS#fetchBody`（`BodyPreference` 截断上限约 2 万字符）→ 落库 → 通知 UI 局部刷新。
4. 附件区按元数据渲染；点击转 `SCN-0005`。
5. 已读标志：本地即时置已读，异步回写服务器（失败不回滚 UI，仅记录待同步）。

失败路径：

- 补拉失败 → 占位改为「正文获取失败，重试」，保留重试入口；不阻塞跳到下一封；
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

`draft`：运行序与测试方案齐；托管浏览器与 sanitizer 未落地。
