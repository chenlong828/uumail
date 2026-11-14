---
layer: design
module: scenes
status: active
updated: 2026-11-14
component: CMP-SCN-READ
---

# CMP-SCN-READ ReadScene 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（场景，`Sendable` 值类型）
- 层 / 类型：L2；阅读、搜索与附件
- 业务价值：把「读本地零网络、缺正文先占位后补拉、补拉先落库再通知、附件单飞与缓存」收在一处；视图与 VM 不再决定先读库还是先拉网。
- 负责 X：`folders/messages/search/attachments` 本地读、`bodyIfCached`、`open` 的补拉事件流、`downloadAttachment` 的缓存/下载/落路径。
- 不负责 Y：选择状态与格式化（`Presentation`）、协议、缓存目录细节（`AttachmentFiles`）。
- 内部逻辑：
  - 本地读方法零网络；`bodyIfCached` 读不到返回 `nil`；纯文本正文在场景内转 HTML（`HTMLText.fromPlainText`）。
  - `open`：命中缓存立即 yield `.cached` 并结束；否则同一 `MessageRef` 单飞 `fetchBody` → 纯文本转 HTML → `applyBody` → yield `.loaded`；失败 yield `.failed` 且不覆盖缓存；消费者取消则不落库。
  - `downloadAttachment`：先查缓存；未命中按 `fileReference` 单飞下载 → `AttachmentFiles.store` → `markAttachmentCached` → 返回 URL；文件先落盘再标记。
- 拥有的数据：无持久数据；在飞请求表（`FlightBoard`）。
- 变化轴：读取策略（远端兜底搜索、附件预览）。
- 公开契约：`CMP-SCN-READ#folders`、`#messages`、`#search`、`#attachments`、`#bodyIfCached`、`#open`、`#downloadAttachment`
- 入口：`Sources/Scenes/ReadScene.swift#ReadScene`、`#MessageRef`、`#BodyEvent`
- 依赖：`MailStore`、`MailDomain`（`MailGateway`、`AttachmentFiles`）。扇出 2 + 端口。
- 冷热：读热、补拉/附件冷。
- 尺寸预算：≤800 行；当前随 `Scenes` 共 691 行。
- 单独运行：`./Scripts/swiftw test --filter ScenesTests`
- 删除测试：删掉后视图与 VM 各自决定读库/拉网与落库 → 规则散落，是真边界。

## 契约卡：ReadScene v1

- 签名：

  ```swift
  public struct MessageRef: Hashable, Sendable { folderID, serverID }
  public enum BodyEvent: Equatable, Sendable { case cached(String), loaded(FetchedBody), failed(MailError) }
  public struct ReadScene: Sendable {
      public init(store: MailStore, account: AccountID, gateway: any MailGateway, files: any AttachmentFiles)
      public func folders() throws -> [Folder]
      public func messages(folderID: String, limit: Int = 200) throws -> [Message]
      public func search(_ query: String, limit: Int = 100) throws -> [Message]
      public func attachments(for ref: MessageRef) throws -> [Attachment]
      public func bodyIfCached(_ ref: MessageRef) throws -> String?
      public func open(_ ref: MessageRef) -> AsyncStream<BodyEvent>
      public func downloadAttachment(_ attachment: Attachment, in ref: MessageRef) async throws -> URL
  }
  ```

- 不变量：前五个方法零网络；`open` 命中缓存不发网络；补拉成功先 `applyBody` 再 yield；失败不覆盖缓存；同一 `MessageRef` / `fileReference` 单飞。
- 错误模式：读库错误直接抛；网关错误包装为 `MailError`（`classify`：原样 `MailError`，其余归 `storage`）。
- 幂等 / 顺序 / 并发：`open` 与 `downloadAttachment` 单飞；重复 `open` 命中已落库正文。
- 超时 / 取消：`AsyncStream.onTermination` 取消补拉任务；取消检查发生在 `applyBody` 之前。
- 一致性：yield `.loaded` 时库已可读；附件 URL 返回时文件已存在、元数据已标记。
- 兼容性：场景持有 `MailStore` 具体类型（L2 依赖 L1a 允许）；`BodyEvent.loaded` 的 `FetchedBody` 已把纯文本转成 HTML（`isHTML = true`），`isTruncated` 保留（D10）。
- 契约测试：`ScenesTests/ReadSceneTests.swift` 6 例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| 本地读零网络 | ✅ | 「folders and search read the local store only」 |
| 缓存正文不发网络 | ✅ | 「a cached body is yielded without touching the gateway」 |
| 补拉一次 → 落库为 HTML → yield | ✅ | 「a missing body is fetched once, stored as HTML, then yielded as loaded」 |
| 失败不覆盖缓存 | ✅ | 「a gateway failure is yielded as failed and does not overwrite the cache」 |
| 附件缓存命中 / 下载并标记 | ✅ | 「downloadAttachment returns a cached file without fetching」「downloadAttachment fetches, stores and records the cache path」 |
| 同一 ref 单飞 | ✅（实现） | `FlightBoard`；未单列并发断言 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 读路径零网络 | fake gateway 调用计数；缓存命中/本地读为 0 |
| 事件序列 | cached 单事件；缺正文 loaded 在 applyBody 之后；失败为 failed |
| 取消 | 终止流后不落库（实现检查；未单列测试） |
| 依赖 | 门 1：`Scenes` 不 import EAS；本场景不 import `Presentation` |

## 依赖约束

- 只依赖 `MailStore`、`MailGateway`、`AttachmentFiles`；不 import `EASClient`/`EASAdapter`/`Composition`。
- 不做格式化与文案；`BodyNotice`/`BodyPresentation` 的映射归 `Presentation`。
- 未实现：25MB 附件上限、断点续传、`AttachmentName` 回退、已读回写（见 `plan/roadmap.md` 与场景卡）。
