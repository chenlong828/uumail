---
layer: design
module: global
scope: project:uumail
status: active
updated: 2026-11-24
component: CMP-WBXML
---

# CMP-WBXML WBXML 编解码

- **单元 / 层**：组件 / L0 工具（纯编解码，无 I/O）
- **业务价值**：EAS 的请求/响应都是 WBXML；把编解码与协议语义分开，升级或修字节边界时只改这一处。
- **负责 / 不负责**：
  - 负责：code page 切换、字符串表、opaque 长度、NUL 结尾、元素树 ↔ 字节、`standard()` 表装载。
  - 不负责：EAS 命令语义、status 码解释、重试/传输（`EASClient`/`URLSessionTransport`）、登录凭据。
- **数据所有权**：无（纯函数与值类型）。
- **公开契约**：`WBXMLCodec`（`encode`/`decode`/`standard()`）、元素中间表示。
- **依赖**：`Foundation`；不依赖 `MailDomain` 或其它组件。
- **尺寸预算**：≤400 行；当前 **363**（`Sources/EASClient/WBXML.swift`，2026-11-24 `wc -l`）。
- **单独运行**：`./Scripts/swiftw test --filter WBXMLTests`（`EASClientTests` 内）。
- **验证计划**：`WBXMLTests` 的 golden fixture round-trip、空元素、code page、opaque 长度、畸形输入。
- **删除测试**：删掉后编解码回到 `EASClient.swift`（1065 行），协议语义与字节边界混在一起 → 真边界。
- **来源**：`history/decisions/2026-11-24-risk-review-decisions.md` D1（预算整理）；
  2026-11-24 从 `CMP-EAS` 预算中析出（同 target、独立文件与测试），`CMP-EAS` 回到 1150/1500。
