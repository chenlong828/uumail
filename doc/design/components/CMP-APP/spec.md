---
layer: design
module: app
status: active
updated: 2026-11-09
component: CMP-APP
---

# CMP-APP AppShell 组件规格

## 模块卡

- 状态：`active`（账号配置页 + 文件夹侧栏 + 邮件列表已落地；正文、阅读、撰写未实现）
- 单元：组件
- 层 / 类型：L2；UI 外壳
- 业务价值：让用户能看见并操作邮箱；没有它，同步能力只存在于命令行。
- 负责 X：窗口与导航、账号配置表单、文件夹选择、邮件列表渲染、同步触发与状态展示。
- 不负责 Y：协议、持久化、同步编排（分别属 CMP-EAS / CMP-STORE / CMP-SYNC）。
- 内部逻辑：启动时从 Keychain 读账号；无账号则显示配置页；有账号则构造 `MailService` 并在启动后刷新。刷新期间列表保留旧数据，失败只在状态栏提示。
- 拥有的数据：无持久数据；账号凭据由 `KeychainAccountStore` 持有，邮件数据归 CMP-STORE。
- 变化轴：窗口形态（单窗口 → 多窗口/菜单栏）、列表与阅读的布局。
- 公开契约：无对外契约；依赖 `MailServiceProtocol`（`MailboxModel` 的注入点）。
- 入口：`Sources/uumail/UumailApp.swift#UumailApp`、`Sources/AppServices/MailboxModel.swift#MailboxModel`
- 依赖：AppServices（MailService、KeychainAccountStore、MailboxModel）、SwiftUI。
- 冷热：热（读本地库）；同步在后台，不阻塞列表。
- 尺寸预算：≤ 120k token；当前远低。
- 单独运行：`./Scripts/make-app.sh && open .build/uumail.app`
- 删除测试：删掉则只能命令行看信，对终端用户等于没有产品。

## 实现进度（2026-11-09）

| 能力 | 代码 | 验证 |
|---|---|---|
| 账号配置（含设备 ID 高级项） | `AccountSetupView.swift` | 窗口截图 |
| 文件夹侧栏 + 邮件列表 | `MailboxView.swift` | 真机 200 封渲染；发件人显示名解析、本地时间；`MailboxModel` 3 个单测 |
| 刷新与失败状态 | `MailboxModel.refresh()` | 单测（失败保留缓存） |
| 正文 / 阅读 / 撰写 | ⬜ | — |

## 待办

- 邮件详情区未实现，点选邮件暂无反馈。
- 无账号时表单空白；考虑 DEBUG 下支持从探针 `.env` 导入。
