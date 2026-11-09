---
layer: history
module: eas
status: frozen
updated: 2026-11-09
---

# W-2026-11-09-eas-probe 工序简报

> 已归档。本文件是过程记忆，不是现行设计依据；结论已落到 `design/components/CMP-EAS/spec.md` 与 `design/components/CMP-EAS/playbook.md`。

## 需求

在不接入公司内网的前提下，从公网确认这条链路是否可行：macOS 上用 EAS 协议以「一台已登记 iPhone」的身份连接公司 Exchange，读邮件、取正文与附件、发信。可行则把协议事实固化为 uumail 的接入基线。

## 背景

Outlook for Mac 依赖 MAPI/HTTP + Autodiscover + EWS，外网这三个虚拟目录都是 404；iPhone 邮件能收，是因为走 EAS 且设备已在网关登记。此前按 MS-ASWBXML 规范字面实现，所有请求都在网关处挂 20 秒后 502，一度误判为网络问题。

## 验收标准

- `OPTIONS` 拿到协议版本，`Provision` 拿到 PolicyKey 并持久化；
- `FolderSync` 取到文件夹树，`Sync` 取到收件箱信封；
- `ItemOperations` 取到 HTML 正文与一个真实附件；
- `SendMail` 返回 `200` + 0 字节 body，收件端可收到；
- 记录每个失败现象与根因，形成可复用的排障顺序。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-EAS-01 | design | CMP-EAS | done | MS-ASWBXML 摘要、MS-ASCMD 命令清单 |
| T-EAS-02 | change | 探针（一次性脚本） | done | WBXML 编解码、Provision 两步握手 |
| T-EAS-03 | change | 探针 | done | Sync 最小体、ItemOperations、SendMail opaque |
| T-EAS-04 | verify | CMP-EAS | done | 能力矩阵逐项实测（列表/正文/附件/发信/文件夹/GAL） |

## 边界

- 只用公司已对移动端开放的官方 EAS 通道，等价于把 Mac 当成一台已登记设备，不做爆破或越权。
- 设备 ID、账号、密码只存在探针目录的 `.env`（600），不进入本仓库。

## 证据

原始脚本、抓包、`inbox.json` 与日志留在 `~/working/公网邮箱访问`，不复制进本仓库（含真实邮件内容与凭据）。
