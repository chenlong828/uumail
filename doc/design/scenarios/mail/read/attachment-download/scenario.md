---
layer: design
module: mail
status: designed
updated: 2026-11-14
flow: mail/read
scenario: SCN-0005
---

# SCN-0005 附件下载与打开

**结果**：用户在阅读页看到附件名与大小，点击后文件落到本地缓存并可预览或用系统默认程序打开；中断后再次点击能续传，超过上限时给出明确提示。

## 入口

- `CMP-SCN-READ#attachments`、`#downloadAttachment`（`design/components/CMP-SCN-READ/spec.md`）
- `CMP-DOMAIN#AttachmentFiles`（生产实现 `FileAttachmentFiles`，见 `design/components/CMP-ROOT/spec.md`）
- `CMP-DOMAIN#MailGateway.fetchAttachment`（经 `CMP-EASADAPTER`）
- `CMP-STORE#markAttachmentCached`（附件元数据写入口）

## 运行序

流程 `F-READ-02`：

1. 阅读页按附件元数据（名称、大小、`fileReference`）渲染列表。
2. 点击 → `AttachmentFiles.cachedURL` 命中则直接返回并打开。
3. 未命中 → `fetchAttachment(fileReference)` 整包下载（base64 解码）。
4. `AttachmentFiles.store` 原子写盘并执行 2 GB 最旧优先淘汰。
5. `markAttachmentCached` 记录缓存路径；返回 URL 给 UI 打开。
6. 同一 `fileReference` 的并发点击共享一次下载（`FlightBoard` 单飞）。

失败路径：

- 超过 25MB → **未实现**，当前不判断大小；
- `404` / `FileReference` 失效 → **未实现** `AttachmentName` 回退；
- 网络中断 → **未实现**断点续传；当前整包下载后原子写，失败则无文件；
- 存储失败 → `MailError.storage` 上抛，UI 提示可重试。

## 不可变引用

- 缓存目录布局与淘汰策略：总上限 2 GB、按修改时间最旧优先（`history/decisions/2026-11-09-attachment-cache-cap.md`，契约在 `CMP-ROOT`/`FileAttachmentFiles`）。
- `FileReference` 直取的协议细节（playbook §5）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0005-01` | 正 | 72KB 附件 → 下载完成、校验一致、可打开 |
| `T-SCN-0005-02` | 正 | 26MB 附件 → 不发起下载，提示改用原客户端 |
| `T-SCN-0005-03` | 正 | 下载中途断网 → 再点续传，最终文件完整且无重复副本 |
| `T-SCN-0005-04` | 反 | `FileReference` 返回 404 → 自动回退 `AttachmentName` 并成功取回 |

## 状态

`designed`（2026-11-14 核对）。入口已从 `MailService` 改为 `ReadScene` + `AttachmentFiles` 端口；实现与验证如下。

实现：`ReadScene.downloadAttachment`（缓存命中、单飞、先落盘再 `markAttachmentCached`）、`FileAttachmentFiles`（确定性文件名、原子写、2 GB 最旧优先淘汰）、`EASAdapter.fetchAttachment` 已落地；`MessageBodyView` 附件条点击调 VM。**未做**：25MB 上限判断、断点续传、`AttachmentName` 回退、真机下载与打开。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0005-01` | 部分（组件级）：`ScenesTests`「downloadAttachment fetches, stores and records the cache path」、`FileAttachmentFilesTests`「a stored file is discoverable and keeps its bytes」；真机「下载完成、可打开」未做 |
| `T-SCN-0005-02` | 未实现：下载前没有 25MB 判断 |
| `T-SCN-0005-03` | 未实现：无断点续传，整包下载后原子写 |
| `T-SCN-0005-04` | 未实现：只按 `FileReference` 取，无 `AttachmentName` 回退 |

未转 `verified` 的原因：01 无真机证据，02–04 均未落地。
