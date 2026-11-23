# 附件下载失败排查证据（2026-11-21）

> 归档说明（2026-11-23）：原始 WBXML 响应、解码后的 xlsx、探针日志与附件文件名含真实邮件数据，均已删除；
> 本文件只保留协议结论与可复核的字节数/耗时。

## 1. 失败样本

一封带两个 xlsx 附件的邮件（主题、发件人、文件名不记录）。

- 请求：`Cmd=ItemOperations`，163 B WBXML（`Fetch/Store=Mailbox` + `FileReference`）。
- 响应：HTTP 200，69,833 B，结构：

  ```
  <ItemOperations>
    <Status>1
    <Response>
      <Fetch>
        <Status>1
        <FileReference>…
        <Properties>
          <ContentType>application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
          <Data>（base64，69,588 字符）
  ```

- base64 解出 52,189 B，zip 的 12 个成员逐个可读、CRC 全通过 → **数据完整，失败在解析**。
- 第二个附件：9,993 B 响应 → 7,311 B，同样完整；同一引用复跑两次响应字节级一致。

## 2. 失效 `FileReference`

把引用末位改一个字符后重发：HTTP 200 / 164 B，
`<ItemOperations><Status>1><Response><Fetch><Status>6`，响应里没有 `Data`。

## 3. `Range` 能力

按 MS-ASCMD 在 `Fetch` 下加 `Options/Range=0-1048575`：HTTP 200 / 13 B，
`<ItemOperations><Status>2`（协议错误）→ 该网关不支持按字节范围取附件。

## 4. 耗时（同一网关、同一设备会话）

| 样本 | 声明大小 | 响应体 | 耗时 |
|---|---|---|---|
| 4.5MB xlsx | 4,586,720 | 6,115,362 | 23.69s |
| 9.5MB 报告 | 9,484,423 | 12,635,165 | 55.19s |
| 28.7MB zip | 28,721,109 | — | 旧 120s 预算超时；600s 预算下 181.55s，取回 28,720,799 B |

约 6s/MB；`EstimatedDataSize` 只是估算（小附件可差 20–40%），不能当完整性校验。

## 5. 复现方式

临时给 `uumailctl` 加了 `attach` 诊断命令（打印 WBXML 交换并保存原始响应），取证后已移除，不在仓库中。
