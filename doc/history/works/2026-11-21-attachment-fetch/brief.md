---
layer: history
module: eas
status: frozen
updated: 2026-11-23
---

# 2026-11-21 附件下载修复（T-1121-01）

> 已归档（2026-11-23）。现行真相见 `design/components/CMP-EAS/spec.md` §设计增量（2026-11-21）与 `playbook.md` §5.5。

## 现象

应用内点击附件提示「网关返回了暂不支持的结果」，任何附件都下不下来。

## 根因

`EASClient.fetchAttachment` 读 `ItemOperations/Data`；网关按 MS-ASCMD 2.2.3.39.2 返回
`ItemOperations/Response/Fetch/Properties/Data`。每次都抛 `malformedResponse("ItemOperations: missing Data")`，
经 `EASAdapter.map` 归成 `.unsupported`。数据本身已完整到货（52,189 B 的有效 xlsx，见 evidence）。

## 范围

- 修附件响应解析（嵌套 `Properties/Data` 优先，直挂 `Data` 兼容；先判 `Fetch/Status`）。
- 附件请求超时 120s → 600s（`EASClient.attachmentResourceTimeout`），其它命令不变。
- 25MB 上限**不做**（用户明确暂缓），断点续传/`AttachmentName` 回退不动。

## 非目标

- 不实现 25MB 上限与 UI 提示（`T-SCN-0005-02`）。
- 不实现断点续传（网关 `Options/Range` 回 `Status=2`，不可用）。
- 不改 `Fetch/Status≠1` 到 UI 文案的映射（仍归 `.unsupported`）。

## 验收

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0005-01` | 正 | 真机取回 52,189 B xlsx，zip 成员全通过；`EASClientTests` 嵌套/直挂/状态 6/600s 预算 4 例 |
| `T-SCN-0005-02` | 正 | 暂缓（用户 2026-11-21 决定），不新增断言 |
| `T-SCN-0005-03` | 正 | 暂缓（网关不支持 Range），不新增断言 |
| `T-SCN-0005-04` | 反 | 暂缓（无 `AttachmentName` 回退） |

## 任务表

| ID | 类型 | 组件 | 状态 |
|---|---|---|---|
| `T-1121-01` | change | `CMP-EAS` | 已完成（2026-11-21） |

## 证据

`evidence/README.md`（响应结构、字节数、耗时与失效引用；原始响应与附件内容在归档时删除，避免真实邮件数据进仓库）。
