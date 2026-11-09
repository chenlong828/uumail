---
layer: works
module: eas
status: active
updated: 2026-11-09
---

# W-2026-11-09-m1-account-access 工序简报

## 需求

把已验证的 EAS 接入从 Python 探针固化成 Swift 组件：账号配置所需的策略握手、文件夹树同步与落库。对应 `REQ-0001`（账号接入，已 accepted）、`SCN-0001`（账号接入与设备身份）。

## 背景

协议事实在 `design/components/CMP-EAS/playbook.md`；契约在 `design/components/CMP-EAS/spec.md` 与 `design/components/CMP-STORE/spec.md`。仓库此前只有文档，本工序是第一次落地代码。

## 验收标准

- `swift build` 与 `swift test` 通过。
- WBXML 编解码与参考实现字节级一致（NUL 字符串、opaque、code page 切换）。
- 错误映射按 `CMP-EAS/spec.md` 的表逐行有测试：401 / 449 / 444 / 502 / 503 / 200 空体 / Sync 3·4。
- `FolderSync` 响应可解析为文件夹列表；`applyFolderSnapshot` 幂等且事务化。
- 命令行 `uumailctl diagnose` 能对真实网关完成 `OPTIONS → Provision → FolderSync`（只读，不写任何数据）。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-1109-01 | change | 工程骨架 | done | Package.swift、.gitignore |
| T-1109-02 | change | CMP-EAS（WBXML） | done | `CMP-EAS/spec.md` §线格式、playbook §4、golden 字节 |
| T-1109-03 | change | CMP-EAS（传输与命令） | done | spec 能力清单与错误映射、playbook §2–3 |
| T-1109-04 | change | CMP-STORE | done | `CMP-STORE/spec.md`、architecture §5 |
| T-1109-05 | change | uumailctl | done | playbook §7 诊断步骤、CMP-EAS 契约 |
| T-1109-06 | verify | CMP-EAS | done | 真实网关只读验证（README 记录在 result） |

## 领取的开放问题

- 无（Q1 正文保留策略、Q2 附件缓存上限与本工序无关）。

## 边界

- 只做只读路径（OPTIONS/Provision/FolderSync）；不实现 Sync 收信、发送与 UI。
- `PolicyKey` 由调用方持有；本工序不落 Keychain（Keychain 属 App 外壳，见 `design/architecture.md` L0）。
- 不复制探针目录的凭据；验证时从环境变量注入。
