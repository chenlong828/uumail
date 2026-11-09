---
layer: plan
module: global
status: draft
updated: 2026-11-09
---

# 路线图

只记里程碑、工序与依赖。需求状态看 `requirements/`，设计真相看 `design/`。
首版范围已于 2026-11-09 确认：REQ-0001…0007 `accepted`（`history/decisions/2026-11-09-scope-baseline.md`）。
工序目录名在立项时按 `works/YYYY-MM-DD-<短名>/` 生成，下表用工序代号指代。

## 里程碑

| 里程碑 | 目标 | 出口判据 | 状态 |
|---|---|---|---|
| M0 协议探针 | 证明外网 EAS 通道可用，锁定线格式、设备身份与命令覆盖 | 命令行跑通 `OPTIONS → Provision → FolderSync → Sync → ItemOperations → SendMail`，实测状态码与能力矩阵成文 | 已完成（`history/works/2026-11-09-eas-probe/`） |
| M1 只读客户端 | 账号接入、文件夹树、列表、正文、附件、离线缓存 | 五个只读场景（SCN-0001…0005）全部 `verified` | 未开始 |
| M2 发送与草稿 | Outbox、SendMail、回复/转发、草稿、Sent 镜像 | send-message 场景 `verified`；离线发送可在联网后只发一次 | 未开始 |
| M3 体验 | Ping、通知、本地搜索、错误恢复与空态 | 新邮件端到端 ≤ 60s 可见（Ping 或轮询）；搜索、通知场景 `verified` | 未开始 |
| M4 加固 | 策略、限流、安全、性能 | 真机矩阵通过；架构测试与性能基线进 CI | 未开始 |

## 工序

| 工序 | 里程碑 | 依赖 | 主要组件 | 出口 |
|---|---|---|---|---|
| W-DOC-01 文档基线 | — | M0 结论 | 全仓 | 已完成：五态文档树成立，架构草案按实测校正（`history/works/2026-11-09-doc-baseline/`） |
| W-M1-01 账号接入与设备身份（`works/2026-11-09-m1-account-access/`） | M1 | W-DOC-01；REQ-0001 已 accepted | CMP-EAS、CMP-STORE | 进行中：协议与落库已通，UI 与账号状态机待补 |
| W-M1-02 文件夹树同步 | M1 | W-M1-01 | CMP-SYNC、CMP-STORE | SCN-0002 `verified` |
| W-M1-03 收件箱增量同步 | M1 | W-M1-02 | CMP-SYNC、CMP-STORE、CMP-EAS | 进行中：分页与原子提交已通，初始同步深度待定；SCN-0003 待 `verified` |
| W-M1-04 正文渲染与附件下载 | M1 | W-M1-03 | CMP-STORE、CMP-EAS、AttachmentCache | SCN-0004、SCN-0005 `verified` |
| W-M2-01 Outbox 与发信 | M2 | W-M1-04 | CMP-OUT、CMP-EAS | 进行中：协议、队列、撰写界面已通；待真机发信验证 |
| W-M2-02 回复/转发与草稿 | M2 | W-M2-01 | CMP-OUT、CMP-STORE | 回复/转发、草稿两个场景 `verified` |
| W-M3-01 Ping 与通知 | M3 | W-M2-01 | CMP-SYNC、通知策略 | Ping 能力结论落 playbook；通知场景 `verified` |
| W-M3-02 本地搜索 | M3 | W-M1-03 | CMP-STORE | 搜索场景 `verified`；FTS 不扫正文列 |

## 批次纪律

- 每个工序一次立一个 `works/` 目录，任务表写在 `brief.md`；一个任务一个对话。
- 组件级 WIP=1：同一时刻只有一个在飞任务改同一组件。
- M1 未通过前不启动 M2；M2 与 M3 可并行但共享 CMP-SYNC，需错峰。
