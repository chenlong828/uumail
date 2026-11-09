---
layer: works
module: global
status: active
updated: 2026-11-09
---

# W-2026-11-09-m4-hardening 结果

## Ping 结论（T-M4-01）

`Ping` 以 `HeartbeatInterval` = 15 / 60 / 300 请求，均在 0 秒内返回 `Status=4`，既非「心跳超时」也非「有变更」。判定：**本网关不支持长轮询**。客户端改为 5 分钟轮询刷新（`UumailApp` 的 task 循环），playbook §3 已记录。

## 加固（T-M4-02/03）

| 项 | 实现 | 验证 |
|---|---|---|
| 限流退避 | `SyncEngine` 捕获 `throttled(after:)`，等待 `min(max(after,1),300)` 秒后重试一次 | 单测：注入 throttled 一次，断言等待 2s 且成功 |
| 附件缓存 | `AttachmentCache.prune` 按修改时间最旧优先淘汰到 2GB 以内 | 2 个单测（超限淘汰、未超限不动） |
| 短查询兜底 | FTS5 trigram 需 ≥3 字符，2 字中文查询回退 `LIKE` | 单测「周报」命中 |

## 性能基线（T-M4-04）

内存库、5,000 封、单文件夹：

```
BASELINE insert5000=0.61s list200=0.002s search=0.001s hits=50 page=200
```

结论：批量落库与列表分页远低于预算；搜索在 5k 规模下毫秒级。测试内阈值：插入 < 20s、列表 < 1s、搜索 < 3s（留足 CI 抖动余量）。

## 安全审计（T-M4-05）

| 面 | 现状 | 风险/备注 |
|---|---|---|
| 凭据 | Keychain（`KeychainAccountStore`）；开发用环境变量 | 无明文落盘；`.env` 在 gitignore |
| 传输 | 默认 TLS 校验；`--insecure` 仅显式开启，未在真实环境使用 | 无证书固定（pinning） |
| HTML | JS 禁用、`default-src 'none'`、远程资源默认阻止、单封可放行 | 未做 URL scheme 白名单（mailto 等） |
| 文件 | 附件名过滤 `/`、`:`；缓存目录在 Application Support | `fileReference` 只参与哈希，不进路径 |
| 数据 | SQLite 明文存储邮件 | 依赖 FileVault；未加密库 |
| 通知 | 只含「N 封新邮件」，不含主题/发件人 | 信息量刻意压低 |
| 调试入口 | `UUMAIL_DEBUG_ENV` 仅在 DEBUG 构建 | Release 构建不含该分支 |

**未覆盖**：证书固定、SQLCipher、审计日志、发信内容校验（收件人域名白名单等）。

## 发信真机验证（授权后执行）

```
$ uumailctl send --to <本人地址> --subject "uumail 自测 20261109-2318"
sent: outbox BFCA3F5C… cleared
$ uumailctl sync --db .build/send-verify.sqlite
+125 added …  收件箱: "uumail 自测 20261109-2318" <- "陈龙07" <chenlong53479@hundsun.com>
```

结论：`SendMail`（opaque MIME、`SaveInSentItems`）被网关接受（outbox 清空 = `200` + 0 字节），邮件真实投递并入收件箱。M2 端到端闭环。

## 裁决

blocker 0 / decision 1（短查询用 LIKE 兜底，牺牲索引换可用性）/ hold 0（发信已获授权并验证）。
