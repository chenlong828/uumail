---
layer: design
module: mail
status: draft
updated: 2026-11-09
flow: mail/read
scenario: SCN-0005
---

# SCN-0005 附件下载与打开

**结果**：用户在阅读页看到附件名与大小，点击后文件落到本地缓存并可预览或用系统默认程序打开；中断后再次点击能续传，超过上限时给出明确提示。

## 入口

- `CMP-EAS#fetchAttachment`
- `AttachmentCache`（architecture §2，L0）
- `CMP-STORE` 附件元数据写入口

## 运行序

流程 `F-READ-02`：

1. 阅读页按附件元数据（名称、大小、contentId）渲染列表。
2. 点击 → 查缓存；命中则直接打开。
3. 未命中 → `CMP-EAS#fetchAttachment(ref)`：优先 `FileReference` 直取；旧版本回退 `AttachmentName` 路径。
4. 流式写盘到缓存目录，边写边校验大小；完成后更新元数据（缓存路径、校验值）。
5. 打开：系统 Quick Look 或默认程序；正文内联图片走同一缓存。

失败路径：

- 超过默认上限 25MB → 提示「请用原客户端下载」，不发起下载；
- `404` / `FileReference` 失效 → 回退 `AttachmentName` 路径重试一次；
- 网络中断 → 保留临时文件，下次点击续传；校验失败则删除重下。

## 不可变引用

- 缓存目录布局与淘汰策略：总上限 2 GB、按修改时间最旧优先（`history/decisions/2026-11-09-attachment-cache-cap.md`，契约在 `design/components/CMP-APP/spec.md`）。
- `FileReference` 优先、`AttachmentName` 回退的技能顺序（playbook §5）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0005-01` | 正 | 72KB 附件 → 下载完成、校验一致、可打开 |
| `T-SCN-0005-02` | 正 | 26MB 附件 → 不发起下载，提示改用原客户端 |
| `T-SCN-0005-03` | 正 | 下载中途断网 → 再点续传，最终文件完整且无重复副本 |
| `T-SCN-0005-04` | 反 | `FileReference` 返回 404 → 自动回退 `AttachmentName` 并成功取回 |

## 状态

`draft`：运行序与测试方案齐；断点续传与缓存未落地。
