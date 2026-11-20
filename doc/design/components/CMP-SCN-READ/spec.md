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
- 负责 X：`folders/messages/search/attachments` 本地读、`bodyIfCached`、`open` 的补拉事件流、`downloadAttachment` 的缓存/下载/落路径；T-1114-10 设计新增 `markReadLocally`/`writeBackMarkRead`/`deleteMessage` 的写编排（2026-11-14 已实现，T-1114-16）；2026-11-20 设计新增 `renderInlineImages(for:html:)`（只取当前正文引用的内联附件，复用 `downloadAttachment`，返回 `data:` 改写后的 HTML）与 internal `InlineImageHTML`（`cid:` 提取/匹配/嗅探/改写）。
- 不负责 Y：选择状态与格式化（`Presentation`）、协议、缓存目录细节（`AttachmentFiles`）。
- 内部逻辑：
  - 本地读方法零网络；`bodyIfCached` 读不到返回 `nil`；纯文本正文在场景内转 HTML（`HTMLText.fromPlainText`）。
  - `open`：命中缓存立即 yield `.cached` 并结束；否则同一 `MessageRef` 单飞 `fetchBody` → 纯文本转 HTML → `applyBody` → yield `.loaded`；失败 yield `.failed` 且不覆盖缓存；消费者取消则不落库。
  - `downloadAttachment`：先查缓存；未命中按 `fileReference` 单飞下载 → `AttachmentFiles.store` → `markAttachmentCached` → 返回 URL；文件先落盘再标记。
- 拥有的数据：无持久数据；在飞请求表（`FlightBoard`）。
- 变化轴：读取策略（远端兜底搜索、附件预览）。
- 公开契约：`CMP-SCN-READ#folders`、`#messages`、`#search`、`#attachments`、`#bodyIfCached`、`#open`、`#downloadAttachment`；T-1114-10 设计新增 `#markReadLocally`、`#writeBackMarkRead`、`#deleteMessage`（2026-11-14 已实现）；2026-11-20 设计新增 `#renderInlineImages(for:html:)`（`#InlineImageHTML` 为 internal，不进入 public 契约）
- 入口：`Sources/Scenes/ReadScene.swift#ReadScene`、`#MessageRef`、`#BodyEvent`
- 依赖：`MailStore`、`MailDomain`（`MailGateway`、`AttachmentFiles`）、`SyncEngine`（写路径；T-1114-10 设计，2026-11-14 已实现）。扇出 3 + 端口；T-1114-10 把场景扇出预算由 1–2 上调至 1–3，仅因 `ReadScene` 新增 `SyncEngine` 直接依赖，P1 已确认（2026-11-14 决策记录；替代方案窄 `SyncWriting` 端口保持扇出 2 仍为被否决项）。
- 冷热：读热、补拉/附件冷。
- 尺寸预算：≤800 行；当前随 `Scenes` 共 1006 行（2026-11-20 `wc -l`，**既有超限**，见 `design/architecture.md` §10 与 `task-spaces/20261120-111818/design.md` §6 R4）；2026-11-20 设计新增 `InlineImageHTML.swift` 约 120 行 + `ReadScene+InlineImages.swift` 约 50 行 → 约 1176 行；本增量不新增 target/依赖，超限登记为既有欠账（`design.md` §6 R4）。
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

- 只依赖 `MailStore`、`MailGateway`、`AttachmentFiles` 与 `SyncEngine`；不 import `EASClient`/`EASAdapter`/`Composition`。
- 不做格式化与文案；`BodyNotice`/`BodyPresentation` 的映射归 `Presentation`。
- 未实现：25MB 附件上限、断点续传、`AttachmentName` 回退；已读回写与删除已实现（本文件增量，T-1114-16，2026-11-14）。

## 设计增量：自动已读与键盘删除（T-1114-10，2026-11-14 设计；T-1114-16 已实现）

- 构造增一个**非可选**写依赖（生产必须注入同一个 `SyncEngine`，测试可注入 fake 端口组成的引擎）：

  ```swift
  public init(store: MailStore, account: AccountID, gateway: any MailGateway,
              files: any AttachmentFiles, writeEngine: SyncEngine)
  ```

  - **替换旧 init，不加重载、不给默认值**：不保留无 `writeEngine` 的构造，避免生产组合根落到只读构造后“可编译但写不出去”。代价是 T-1114-16 必须同一 change 机械更新 `AppComposition`/`CommandLineComposition`，登记为 `CMP-ROOT（仅装配）` 例外。
  - 直接依赖具体 `SyncEngine` 而非另抽 `SyncWriting` 端口：`SyncEngine` 是集合 `SyncKey` 与 FIFO 门的唯一 owner，窄端口只是同形转发；`Scenes` target 本就依赖 `SyncEngine`。测试用真实引擎 + fake gateway（读/写）/store，测试面仍是两个写方法。P1 已接受扇出 1–3（2026-11-14 决策记录）；窄端口方案保留为被否决记录。

- 新增三个方法，计时与临时隐藏都不在本组件：

  ```swift
  public enum WriteOutcome: Equatable, Sendable { case succeeded, failed(MailError) }

  @discardableResult
  public func markReadLocally(_ ref: MessageRef) throws -> Bool
  public func writeBackMarkRead(_ ref: MessageRef) async -> WriteOutcome
  public func deleteMessage(_ ref: MessageRef) async throws
  ```

- `markReadLocally`：只调 `store.markRead`，零网络；返回是否发生 0→1。本地失败**原样抛出**（类型可能是 `MailStoreError`/GRDB `DatabaseError`，不是 `MailError`），`ReadScene` 不在此处增加分类；调用方（2026-11-16 起为 `MailboxViewModel.performMarkRead`，自动计时与手动置读共用）在用户可见前把非 `MailError` 归一为 `.storage(reason:)`：自动计时路径忽略错误、不回写、不展示；手动入口经 `ErrorText` 展示中文。
- `writeBackMarkRead`：只调 `writeEngine.markRead`；成功返回 `.succeeded`；任何失败（含 `MailError`、存储错误）归为 `.failed(MailError)`，不抛、不回滚、不重试。分类复用 `classify`：`MailError` 原样，其它归 `storage(reason:)`。
- `deleteMessage`：只调 `writeEngine.deleteMessage` 并把非 `MailError` 归为 `storage`；不本地预删、不捕获业务错误、不做选中推进（PRES 负责）。`CancellationError` 原样传播（不归 `storage`），由 PRES 按取消恢复。
- 不变量改写：`folders/messages/search/attachments/bodyIfCached/open` 仍零网络；`markReadLocally` 只写本地；只有 `writeBackMarkRead`/`deleteMessage` 触网，且只经 `SyncEngine` 的门。**该改写是本次唯一需要修订的既有不变量**，不得把两个写方法塞进「读路径」叙述。
- 依赖：仍只依赖 `MailStore`、`MailDomain`（`MailGateway`/`AttachmentFiles`）与 `SyncEngine`；不 import EAS/Presentation。`Scenes` 已依赖 `SyncEngine`，不新增 target/组件。
- 尺寸：`ReadScene` 当前 191 行；预计 +45（三个方法、分类与文档），组件总量约 740/800。
- 测试：`ReadSceneTests` 补「先本地后回写（fake gateway 记录调用顺序）」「回写失败本地仍已读」「删除只在网关成功后软删」「网关失败不软删」「非 MailError 归 storage」；既有 6 例不回归。
- 测试构造点：`ReadScene` 的四处构造（`AppComposition`、`CommandLineComposition`、`Tests/ScenesTests/ReadSceneTests.swift`、`Tests/PresentationTests/Support.swift`）必须同批更新；测试用真实 `SyncEngine` + fake `MailGateway`/`SyncStore`，写端口用测试 target 的 `UnsupportedWriteGateway` 或记录 fake，不保留无 `writeEngine` 的只读重载。

**实现（2026-11-14）**：`ReadScene` 构造改为非可选 `writeEngine`；`markReadLocally` 只写本地，`writeBackMarkRead` 返回 `.succeeded/.failed` 不抛，`deleteMessage` 只在服务器成功后由 `MailStore.commitDelete` 软删，取消原样传播。`ScenesTests` 32 例绿，含本地先行、回写失败不回滚、删除失败不软删、取消传播、非 MailError→storage、删除后下一轮同步不复活。

## 设计增量：手动置读复用（REQ-0019，2026-11-16）

- `MailboxViewModel.markSelectedRead()`（P2 待确认）复用既有 `markReadLocally` / `writeBackMarkRead` 两阶段，不新增 `ReadScene` 方法，不改 `MailWriteGateway`/`SyncStore`/`MailStore` 契约、schema 或协议。
- 自动计时与手动入口都经 `MailboxViewModel.performMarkRead`；`MailboxDwell` 不再直接调用 `ReadScene`。`ReadScene` 的本地读方法仍零网络，写方法仍只经 `SyncEngine` 的 FIFO 门。
- 并发/幂等由 `MailboxViewModel` 的 `@MainActor` 串行与 `markReadLocally` 的 0→1 返回值保证：第二次调用返回 false，不启动第二次回写。
- 错误类型：本增量**不改变** `markReadLocally` 的 `throws` 表面（仍原样抛存储错误）；用户在 `markReadErrorText` 看到的中文由 `MailboxViewModel.performMarkRead` 归一后交给 `ErrorText`，`ReadScene` 不 import PRES、不拼文案。若后续把 `markReadLocally` 也统一 `classify` 为 `MailError`，调用方归一仍兼容，但不是本批范围。
- 不改 `ReadScene.deleteMessage`、附件、正文打开/缓存/补拉；本增量只登记调用方变化，不新增场景断言。


## 设计增量：内联图片渲染（REQ-0025 / SCN-0019，2026-11-20）

- 来源：`REQ-0025`（`feature`，`accepted`）/ 新场景 `SCN-0019`（`designed`）。完整论证见 `task-spaces/20261120-111818/design.md`。
- 新增 internal 纯函数（`Sources/Scenes/InlineImageHTML.swift`，只 import Foundation + `MailDomain`）：

  ```swift
  enum InlineImageHTML {
      struct Match { let source: String; let attachment: Attachment }
      static func sources(inHTML html: String) -> [String]
      static func normalizedCID(_ cid: String) -> String
      static func matches(inHTML html: String, attachments: [Attachment]) -> [Match]
      static func dataURL(for data: Data) -> String?
      static func replacingSources(inHTML html: String, with replacements: [String: String]) -> String
  }
  ```

  - `sources`：只提取**独立属性名** `src`（不匹配 `data-src`/`srcset`）里以 `cid:` 开头的值（大小写无关），按出现顺序去重，返回原始拼写；不匹配正文文本/`href`/CSS。
  - `normalizedCID`：去首尾空白 → 去 `cid:` 前缀 → 去外层 `<>` → 百分号解码 → 小写。
  - `matches`：先按**服务器返回的 `contentID`** 精确匹配（`normalize(contentID) == normalize(cid)`，含 `@` 全串；2026-11-21 起）。`contentID` 命中集合非空时只用它；否则回退到既有名字规则：`normalize(displayName) == normalize(cid)`、`== normalize(cid 的 @ 前 local part)`，或 `displayName` 带已知图片扩展名时 `normalize(去扩展名的 displayName) == normalize(cid 的 @ 前 local part)`。按 `fileReference` 去重后恰好 1 个才返回，0/≥2 个跳过。不猜、不按顺序兜底、不跨邮件；非图片扩展名不做去扩展名匹配。
  - `dataURL`：按图片魔数（PNG/JPEG/GIF/WebP/BMP/TIFF/HEIC）生成 `data:image/...;base64,...`；非图片返回 nil。
  - `replacingSources`：一次 `NSRegularExpression` 匹配**独立属性名** `src`（不匹配 `data-src`/`srcset`；单/双/无引号），只替换值区间；没有替换项的引用保持原样；保留引号、其它属性、其余字节；相同引用多次出现都替换。
- 新增 public 方法（`Sources/Scenes/ReadScene+InlineImages.swift`；`ReadScene` 仍是值类型，不新增依赖）：

  ```swift
  extension ReadScene {
      /// 当前正文实际引用的内联附件 → data: 改写后的 HTML；无可用替换时返回 nil。
      /// 冷路径；缓存命中不触网；单张失败/超限/取消 → 跳过该张，不抛错。
      public func renderInlineImages(for ref: MessageRef, html: String) async -> String?
  }
  ```

  - 流程：`attachments(for:)` → `InlineImageHTML.matches` → 按 `fileReference` 去重 → 顺序调用既有 `downloadAttachment(attachment, in: ref)`（同一附件单飞 + `AttachmentFiles` 缓存 + `markAttachmentCached`）→ `Data(contentsOf:)` → `InlineImageHTML.dataURL` → `replacingSources`。
  - 同一附件被多次引用只下载/编码一次；`Task.isCancelled` 在每个附件之间检查；顺序取（不并发打网关）。
  - 单张失败/坏数据/超过 20MB guard（实现 guard，非验收契约）→ 跳过；全部失败返回 `nil`。
- 不变量：
  - `open`/`bodyIfCached`/`attachments` 的语义与零网络性**不变**；本方法不被 `open` 的流等待，由 PRES 另起任务调用。
  - 只取当前正文实际引用的附件；未引用附件不预取；不因 `cid:` 向第三方发请求。
  - 同一 `fileReference` 与附件条点击共享 `FlightBoard`/缓存，不重复下载；失败不重试循环。
  - 不改 `downloadAttachment` 的签名/语义；不 import `EASClient`/`EASAdapter`/`Presentation`/WebKit；`MailGateway`/`MailStore`/`MailDomain` 契约不变。
- 尺寸：`InlineImageHTML.swift` 约 120 行、`ReadScene+InlineImages.swift` 约 50 行（均 <300）；`Scenes` 由 1006 → 约 1176（既有 800 行预算已超，登记为既有欠账）。
- 测试：`ScenesTests/InlineImageHTMLTests`（提取/规范化/唯一匹配含去扩展名/歧义/嗅探/只改 `src` 值）与 `ScenesTests/ReadSceneInlineImageTests`（只取被引用附件、同附件多次引用只取一次、缓存命中 0 次 gateway、单张失败跳过、超限跳过、取消提前返回）；fake gateway/files 记录调用集。
- 2026-11-21 增量（REQ-0025 / `T-1121-02`）：`Attachment.contentID` 由 `EASClient` 解析、`MailStore` v11 持久化后，
  `matches` 以它为首选匹配（见上）；名字规则保留为回退。`ContentId` 与 `cid:` 都是不透明串，只做规范化后的全串相等；
  同 `ContentId` 多附件仍按歧义跳过。旧邮件（v11 前同步）`contentID == nil`，行为与 2026-11-20 版一致。
- 定级/确认：**P2**（首版：场景公开面 additive + internal 纯函数；无 schema/`MailDomain` 契约/依赖/热路径依赖变更）。
  2026-11-21 的 `ContentId` 持久化按 **P1** 处理（`attachments` schema + `Attachment` 公开契约），已人工确认，见
  `doc/history/decisions/2026-11-21-inline-image-content-id.md`。`renderInlineImages(for:html:)` 公开面已**人工确认 pass（A，2026-11-20）**，记录见 `doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`；D2/D4/D7 仍为默认确认（未经人工），见 `task-spaces/20261120-111818/design2.md` §8。

- 实现进度（2026-11-21，`T-1121-05`）：`InlineImageHTML.matches` 增加 `contentID` 优先匹配（名字规则保留为回退）；
  新增 `InlineImageHTMLTests.matchesOpaqueCIDByContentID`、`contentIDTakesPrecedenceOverNames`、`duplicateContentIDIsIgnored`
  与 `ReadSceneInlineImageTests.opaqueCIDUsesContentID`；`Scenes` 合计 1188 行（低于 1200 拆分触发线）。
- 实现进度（2026-11-20，`T-1120-01`）：已新增 `Sources/Scenes/InlineImageHTML.swift`（120 行，internal 纯函数）与 `Tests/ScenesTests/InlineImageHTMLTests.swift`（7 例：`sourcesFindCIDSourcesOnly`、`normalizationHandlesCasePercentAndBrackets`、`matchesDisplayNameAndLocalPart`、`matchesStemWhenCIDOmitsExtension`、`ambiguousReferenceIsIgnored`、`replacingOnlyTouchesSourceValues`、`dataURLSniffsCommonImageFormats`）；`ScenesTests` 绿、架构 4 门 PASS；N6 像素 guard 按 D1 未实现。
- 实现进度（2026-11-20，`T-1120-02`）：已新增 `Sources/Scenes/ReadScene+InlineImages.swift`（32 行，public `renderInlineImages(for:html:)`）与 `Tests/ScenesTests/ReadSceneInlineImageTests.swift`（5 例）；复用 `downloadAttachment`/`AttachmentFiles`/`FlightBoard`；20MB 字节 guard 保留，单张失败/坏字节/取消跳过；`Scenes` 合计 1158 行（本批新增 152，≤170）；`ScenesTests` 51 例绿、架构 4 门 PASS。
- 实现进度（2026-11-20，`T-1120-01` B2 修复）：`InlineImageHTML` 的 `sources`/`replacingSources` 改为先定位 `<img>` 标签、再在其内匹配独立 `src` 属性；标签内其它属性值先掩码，正文文本/其它标签/属性值内的 ` src=` 不再被收集或改写；无引号自闭合 `/>` 的 `/` 保留在替换值之外；`src=" cid:x "` 的 key 统一 trim。`InlineImageHTMLTests` 增至 11 例（新增正文空白、其它属性值、`<video>`/`<image>`、无引号自闭合、引号内空白 4 例）；`Scenes` 合计 1175 行，`InlineImageHTML.swift` 137 行；`ScenesTests` 绿、全量 347 tests / 57 suites、架构 4 门 PASS。
