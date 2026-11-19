---
layer: history
module: mail
status: frozen
updated: 2026-11-19
---

# 远程图片实际加载的运行载体 ATS 例外：P2 人工确认与实现边界（2026-11-19）

## 背景

`REQ-0024`（`quality`，`accepted`）：用户点「加载远程图片」后，当前邮件里的远程图片仍空白。需求阶段确认开关/状态机/CSP 两档已由 `SCN-0013` 验证，缺口在「图片真正被请求/渲染」；样本图片 4/4 为明文 `http`，应用 `Info.plist` 无任何 ATS 键。

设计期用 L2 探针（生产 `MessageWebView`/`MessageBodyStyle` + 受控 http 源 + 同一二进制换 carrier）证实：放行档 CSP 已允许 `http:`，但**带 bundle `Info.plist` 且无 ATS 例外的载体里图片请求 0 次出网**（受控服务端 0 命中、`img.naturalWidth=0`）；同一二进制换上含 `NSAllowsArbitraryLoadsInWebContent=true` 的 bundle plist 后请求到达并渲染。另测得：`127.0.0.1`/`localhost` 被 ATS 豁免（不能用于判 ATS）；裸可执行（`swift run` 形状）无 bundle plist、本来即可加载；加该键后 URLSession 明文 http 仍被 ATS 拒绝（应用网络路径不放宽）。证据：`task-spaces/20261119-213812/evidence/remote-image-probe/`。

按 `arch-design-spec`，本次改动是**交付载体/安全策略单点**（新增受版本管理的 `Resources/Info.plist` + `make-app.sh` 装机方式调整），不改模块切分、公共契约、schema、数据所有权、分层依赖或热路径，定为 **P2**；按 `REQ-0024` D4 与 `auto-confirm` §3，放宽 ATS 属安全策略变更，必须人工确认。设计节点于 2026-11-19 提交 `mcp__agentflow__confirm`（单问题，3 选项），**确认前未改实现代码、未重建 `dist`**。

## 确认来源与范围

- 确认通道：本 run（`task-spaces/20261119-213812`）的 `[人工确认]` 回复；时间：2026-11-19。
- 问题：是否批准在 release app bundle 增加 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent=true`，以修复「加载远程图片」开启后图片仍空白？
- **人工确认：问题如上；决定 pass；意见「批准：仅加 `NSAllowsArbitraryLoadsInWebContent=true`（推荐）」**；无可选项之外的附加条件、无收窄、无改选。
- 影响范围：`REQ-0024` / `SCN-0018` 的实现与 L1/L2 验证；`SCN-0013`/`SCN-0004`/`SCN-0010`/`SCN-0012`/`SCN-0015`/`SCN-0016` 只作回归。**不改** `SCN-0013` 的 `verified` 状态与断言（只读）。
- 本记录由设计节点按人工回复落盘，只记录确认事实与影响，不代签、不扩写为「发起人确认」。

## 决定

| # | 项 | 结论 |
|---|---|---|
| D1 | 修复机制 | 只在交付载体加 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent = true`；**不加** `NSAllowsArbitraryLoads`、**不加** `NSExceptionDomains`，不做全局放宽。 |
| D2 | 配置单一来源 | 新增受版本管理的 `Resources/Info.plist`（与现 `make-app.sh` heredoc 逐键一致）；`Scripts/make-app.sh` 的 heredoc 改为 `cp Resources/Info.plist "$APP/Contents/Info.plist"`。release 构建、图标、ad-hoc 签名、`build-info.txt`、`dist` 路径不变。 |
| D3 | 代码零改动 | `MessageWebView`/`MessageBodyStyle`/`MessageBodyView`/`MailboxViewModel`/`ComposeEditor` 不改：`loadHTMLString(_, baseURL: nil)`、CSP 两档、禁 JS、白底、`lastRender` guard 原样。 |
| D4 | 安全边界 | 例外只作用于 WKWebView 内容（正文 + 撰写编辑器），两处图片仍由同一 `allowRemoteContent` 放行档 CSP 门控（默认/关闭 0 请求）；URLSession/EAS 明文 http 仍受 ATS（L2 实测）。 |
| D5 | 运行载体 | `swift run`（无 bundle `Info.plist`）本来即可加载明文 http 图片，本次不为它加 shim；发布/开发统一 `./Scripts/make-app.sh && open dist/uumail.app`。实现里程碑结束按 `AGENTS.md` 重建 `dist`（任务出口 A6 要求的打包，不是对外发布/改版本号）。 |
| D6 | 验证载体 | 探针 `.app` 的 `Info.plist` = `Resources/Info.plist` 原样副本；图片 URL 必须用解析到受控服务器的**非本地主机名**（`127.0.0.1`/`localhost` 被 ATS 豁免，会假绿）；含无 ATS 负控制 + `data:` 正控制。证据最低 L2，不上 L3/L4。 |
| D7 | 场景归属 | 新场景 `SCN-0018`（`mail/read/remote-image-load`，`designed`）认领实际加载/阻断零请求/载体配置；`SCN-0013` 保持 `verified` 只读；`SCN-0004` 的 `T-SCN-0004-03` 不并入。 |

## 影响

- 新增资源文件 `Resources/Info.plist`（约 35 行）；`Scripts/make-app.sh` 去掉内联 heredoc。`Sources/uumail` 行数零变化，不新增 target/依赖/第三方库。
- 不改 `MailDomain`/`MailStore`/`Scenes`/`CMP-PRES` 契约、schema、协议、数据所有权；不写偏好/Keychain。
- `SCN-0018` 验收：`T-SCN-0018-01`（L2 正例 + 负控制/正控制）、`T-SCN-0018-02`（L1 键断言 + L2 URLSession 仍受限）、`T-SCN-0018-03`（L1 脚本接线 + `dist` plist/`build-info` 一致；L2 裸可执行正例）；回归 `SCN-0013-01..04` 与 `SCN-0004`/`SCN-0010`/`SCN-0012`/`SCN-0015`/`SCN-0016`。
- 状态位：本确认不翻转任何状态。`SCN-0018` 保持 `designed`、`REQ-0024` 保持 `accepted`；实现与验证通过后由收尾按评审清单翻转（`SCN-0018 → verified`、`REQ-0024 → delivered`）。
- 回滚：删除 `NSAppTransportSecurity` 字典、`make-app.sh` 恢复内联 heredoc（或保留资源文件但去键）；纯配置、无数据/契约迁移。

## 未采纳 / 明确不做

- 全局 `NSAllowsArbitraryLoads`（会放宽 URLSession/EAS 明文路径）——仅作未来若目标系统不支持 WebView 例外时的退路，需重新确认。
- 应用代理取图/自定义 scheme handler、正文 URL `http→https` 改写：违反 `SCN-0013` 不可变引用「正文 HTML/sanitizer 不被无谓改写」，且代理抓图仍受 ATS；属扩范围。
- 伪造 Referer/Cookie、图片缓存/离线保存/查看器、自动加载、域名白名单、`cid:` 解析、懒加载、开 JS、放宽 `default-src 'none'`。
- L3 截图/OCR、L4 AX：本卡最高 L2（模型不支持读图）；A5 真实样本冒烟为发布前/人工项，不替代 L1/L2 断言。

## 落点

- 需求/场景：`doc/requirements/REQ-0024-remote-image-actual-load.md`（`accepted`，补「设计落地」说明）、`doc/design/scenarios/mail/read/remote-image-load/scenario.md`（`SCN-0018`，`designed`）。
- 规格：`doc/design/components/CMP-APP/spec.md` 的 2026-11-19 增量（P2 已人工确认；实现后追加进度行）。
- 过程：`task-spaces/20261119-213812/design.md`（§12 确认结果）、`index.md`、`evidence/remote-image-probe/`。
- 实现：`Resources/Info.plist`（新）、`Scripts/make-app.sh`（改）；代码零改动。
- 排期/任务：由 task-split 建任务；本记录不含 `T-` 号。
