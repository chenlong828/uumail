---
layer: plan
module: global
status: draft
updated: 2026-11-13
---

# 风险

只记跨工序风险：触发信号、影响、缓解、落点。单工序内部风险写在该工序 brief 里。

| ID | 风险 | 触发信号 | 影响 | 缓解 | 落点 |
|---|---|---|---|---|---|
| R1 | 网关设备清单被清理或换机 | 所有命令 `200` 空 body、写命令 `401`；短信回执显示设备被删 | 客户端立即不可用，且错误表现为「成功但没数据」，最易误判 | 把「0 字节 200」映射为 `deviceNotRegistered` 并给出登记指引；启动时做一次轻量探活 | `design/components/CMP-EAS/playbook.md` §6 |
| R2 | 公司收紧 EAS 或要求 MDM/零信任客户端 | IT 公告、网关拒绝新设备、`OPTIONS` 不再返回命令列表 | 项目前提失效 | 只走官方移动端通道，不绕过认证；上线前与 IT 确认合规；能力探测失败时明确提示 | `design/architecture.md` §7 |
| R3 | 公司迁移到 Exchange Online / 关闭本地 EAS | IT 公告、账号迁云、本地 EAS 网关下线 | 本项目前提消失：Basic 认证链与新协议均不在范围内 | 项目定位即私有化 Exchange 客户端（T13），不做假兼容；迁移即重新立项评估 | `history/decisions/2026-11-09-scope-baseline.md`、`design/architecture.md` T13 |
| R4 | GAL 与联系人不可用 | `Search`/`Find`/`ResolveRecipients` 非成功状态 | 撰写时无法目录补全，与「企业邮箱体验」预期有落差 | 首版只做本机通讯录 + 收件人历史；UI 不暴露 GAL 入口；能力矩阵标注实测结论 | `design/components/CMP-EAS/playbook.md` §5 |
| R5 | 只支持 5 分钟轮询，新邮件有延迟 | 通知与列表最多晚一个轮询周期 | M3 体验目标（≤60s）在本网关不可承诺 | Ping 实测不支持长轮询（`Status=4`）；固定 5 分钟轮询并在 UI 标注，不做 IMAP 式长连接 | `design/components/CMP-EAS/playbook.md` §5.2、`design/architecture.md` T3 |
| R6 | 大邮箱导致本地库膨胀 | 库文件增长、列表打开变慢、备份失败 | M1 可用性下降 | 按文件夹/时间窗口裁剪正文，列表只保信封；附件 2 GB 最旧优先淘汰 | `design/components/CMP-STORE/spec.md`、`design/components/CMP-APP/spec.md` |
| R7 | HTML 邮件攻击面 | 脚本、远程图片、追踪像素、畸形样式 | 隐私泄露与渲染崩溃 | WKWebView 关脚本 + CSP；默认阻止远程资源；正文经 sanitizer 再渲染 | `design/architecture.md` T5 |
| R8 | 服务器限流 | `503` + `Retry-After`、批量 Sync 变慢 | 同步卡死或账号被临时封禁 | 单账号串行、全局退避、Retry-After 优先；Ping 与 Sync 不并发轰炸 | `design/components/CMP-SYNC/spec.md` |
| R9 | WBXML 编解码边界 | 空元素、code page 切换、NUL 结尾、opaque 长度 | 请求被网关挂起 20s 后 `502`，表现为「网络问题」 | golden fixture round-trip；以探针真实字节为准，不照抄规范写法 | `design/components/CMP-EAS/playbook.md` §4 |
| R10 | 时间与排序错乱 | 列表顺序与服务器不一致、跨时区显示偏差 | 用户找不到新邮件 | 统一以服务器 `DateReceived` 排序，本地接收时间只做兜底 | `design/components/CMP-STORE/spec.md` |
| R11 | 抓包样本含敏感内容 | 真实邮件正文/主题进入仓库或日志 | 合规事故 | 已决：脱敏后入仓（`history/decisions/2026-11-09-scope-baseline.md` 决策记录）；脱敏脚本与样本同目录，`.env`、`logs/`、`output/` 不入库，提交前检查 | `history/decisions/2026-11-09-scope-baseline.md`、`design/architecture.md` §7.3 |
| R12 | 传输与静态数据加固缺口 | 无 certificate pinning；本地库与缓存明文、无 SQLCipher；无审计日志 | 内部 CA 中间人或磁盘/备份泄露时邮件内容暴露 | 凭据只进 Keychain；库与缓存依赖 FileVault；附件名过滤路径分隔符；不做 pinning/SQLCipher 为已知接受项，后续按需补 | `design/components/CMP-STORE/spec.md` 数据所有权、`design/components/CMP-APP/spec.md` |
| R13 | 发送只入队后用户看不出待发/失败 | 离线或投递失败后，列表与状态栏没有 pending/failed 计数；只有撰写页短暂显示「已加入发件箱」 | 用户误以为邮件已发出，重复发送或错过重试 | 组合根已有 `OutboxPump` 自动重投；短期靠撰写页状态文案，后续加列表/状态栏角标（`Outbox.pending` 已可读） | `design/components/CMP-PRES/spec.md`、`CMP-APP/spec.md`、`CMP-OUT/spec.md` |

## 风险等级口径

- 高：直接使项目不可用或造成合规事故（R1、R2、R11）。
- 中：影响关键旅程但可降级（R3、R4、R5、R6、R8、R12、R13）。
- 低：局部体验或可回滚（R7、R9、R10）。
