---
layer: design
module: eas
status: active
updated: 2026-11-14
component: CMP-EAS
---

# CMP-EAS 接入手册（playbook）

**性质**：本组件在真实公司环境里的接入事实与操作步骤，属现行真相。证据来源是 2026-11-08 的探针实施（`~/working/公网邮箱访问`，含脚本、抓包与实测记录），结论已收敛进本文件；原始材料只作证据，不作设计依据。

> 凭据、账号、设备 ID、主机名一律不入本文件。运行时值只放部署配置或 Keychain。

## 1. 环境事实

| 项 | 实测结论 | 对设计的影响 |
|---|---|---|
| 外网暴露面 | 只开 443；仅发布 `/Microsoft-Server-ActiveSync` | 客户端只能走 EAS，MAPI/EWS/IMAP 方案不可行 |
| 其它虚拟目录 | `/EWS`、`/autodiscover`、`/mapi/emsmdb` 外网均 404 | **自动发现不可用**，账号配置以手填服务器为主路径 |
| 服务端 | Exchange 2016（`X-Owa-Version: 15.2`），前置一层 EAS 感知网关 | 网关行为必须按实际抓包对待，不能只看 MS 规范 |
| 认证 | Basic over TLS，认证头用 `域\账号` | 凭据只存 Keychain，禁止写日志 |
| 协议版本 | `MS-ASProtocolVersion: 16.1` 可用 | 首版 16.1；降级链 14.1 → 14.0 保留 |
| 设备身份 | 网关按 `DeviceId` 登记；未登记设备读命令 `200` 空 body、写命令 `401` | **DeviceId 必须是网关里已登记并激活的值**，不能随机生成 |
| 传输编码 | 响应可能 gzip | 按 `Content-Encoding` 解压 |
| 会话 | `OPTIONS` 下发 `Set-Cookie`（`X-BackEndCookie`），带 Cookie 更稳 | 传输层维护 Cookie jar |

## 2. 请求骨架

```
POST https://<host>/Microsoft-Server-ActiveSync?Cmd=<命令>&User=<无域账号>&DeviceId=<id>&DeviceType=iPhone
Authorization: Basic base64("<域>\<账号>:<密码>")
User-Agent: Apple-iPhone18C4/2307.90        # 模拟 iOS，按实测值固定
MS-ASProtocolVersion: 16.1
X-MS-PolicyKey: <key>                        # Provision 后常驻
Content-Type: application/vnd.ms-sync.wbxml
Accept-Encoding: gzip, deflate
```

- `User` 参数**不带域**；带域会被网关挂起后 `502`。域只出现在认证头里。这是最容易踩的一处，开源实现 PyActiveSync 也是拆成 `username`（认证）与 `user`（参数）两个字段。
- 缺 `Cmd/User/DeviceId/DeviceType` 任一参数，网关直接 `444` 断连，不会有 EAS 层错误。

## 3. 会话流程

```
OPTIONS（裸 URL）
  → Provision 第一步：DeviceInformation + PolicyType（不带 Data）→ 临时 PolicyKey
  → Provision 第二步：PolicyType + PolicyKey + Status=1 → 正式 PolicyKey
  → FolderSync(SyncKey=0) → 文件夹树 + 新 key
  → Sync(CollectionId=<收件箱>, SyncKey=0) → 只回新 key
  → Sync(同一 CollectionId, 新 key) → 返回 Add/Change/Delete 与邮件信封
  → ItemOperations / Fetch → 正文、附件
  → SendMail(Mime=opaque) → 200 + 0 字节 body 即成功
```

要点：

- `OPTIONS` 必须打**裸 URL**，带 `?Cmd=` 会被网关吞成 `200` 空响应。
- `Provision` 的 `DeviceInformation` 必须**直接挂在 `Provision` 下**，多包一层 `Settings` 会得到 `Status=2`。
- `PolicyType` 用 `MS-EAS-Provisioning-WBXML`，且**不能带 `Data`**。
- `SyncKey=0` 的首次 Sync 只返回新 key，必须用新 key 再 Sync 才拿到条目。
- **分页靠「本轮新增数」判断，不能只信 `MoreAvailable`**（2026-11-09 实测）：服务器每轮最多回 `WindowSize` 条，`MoreAvailable` 常常不出现，但下一轮仍有 25 条。客户端应循环调用，直到某轮新增数少于窗口大小；`MoreAvailable` 只作为提前继续的附加信号。
- `Sync` 请求体保持最小：`Sync/Collections/Collection/{SyncKey, CollectionId, WindowSize, Options}`。多出的顶层 `SyncKey`、`Class`、`GetChanges` 会让 Exchange 回 `Sync/Status=4`。
- `FolderSync` 每次按 `SyncKey=0` 取全量树；增量 key 只用于发现「树变了」。

## 4. 线格式（WBXML）要点

EAS 用 WBXML 1.3。以下四点按**实测字节**而非规范字面实现：

| 点 | 做法 | 不这么做的后果 |
|---|---|---|
| 内联字符串 | `STR_I(0x03)` + UTF-8 字节 + **`0x00` 结尾** | 按 MS-ASWBXML 的「长度前缀」写，网关解析失败，挂 20s 后 `502` |
| opaque（附件、MIME） | `OPAQUE(0xC3)` + mb_uint 长度 + 原始字节 | `SendMail` 的 `Mime` 若按 base64 字符串送，同样挂 20s 后 `502` |
| 空元素 | 只发 token，不跟内容与 END | 多余 END 造成后续 token 错位 |
| code page | 遇到 token 不在当前页就先 `SWITCH_PAGE(0x00, page)` | 跨页标签编到错误的 token |

**这不是本网关的怪癖**：EAS-4-TbSync（`wbxml.mjs`）与 PyActiveSync（`_wbxml.py`）都用「`STR_I` + UTF-8 + `0x00`」与 opaque 原始字节，说明 NUL 结尾与 opaque 才是 EAS 的真实线格式，规范写法只在部分服务端可容忍。

编解码 token 表以探针目录的 `spec/eas_tokens.json`（26 个 code page、600+ token，由 MS-ASWBXML 页面抓取生成）为基，样本用探针脱敏件做 round-trip。

## 5. 能力矩阵（实测，作为首版 UI 可见性的依据）

| 能力 | 结论 | 依据 |
|---|---|---|
| 邮件列表 | ✅ | 30 封，主题/发件人/时间/已读 |
| HTML 正文 | ✅ | `ItemOperations` 取到约 2 万字符 HTML |
| 附件下载 | ✅ | `FileReference` 直取，72KB 落盘 |
| 发信（含附件） | ✅ | 发给自己 + 抄送外部地址，`200` + 0B |
| 回复 | ✅ | 同一 `SendMail` 通道 + `In-Reply-To`/`References` 头 |
| 建/删文件夹 | ✅ | `FolderCreate` / `FolderDelete` 均 `Status=1` |
| 联系人文件夹 | ⚠️ | 文件夹存在，Sync `Status=1` 但无条目（疑似为空） |
| GAL 目录搜索 | ❌ | `Search` → `Store Status=2`；`Find` → 2；`ResolveRecipients` → 5 |
| Ping 长轮询 | ❌ 不支持 | 三档心跳均立即 `Status=4`，见 §5.2；客户端改 5 分钟轮询 |
| MoveItems | ⚠️ 未验证 | M1 不依赖；移动先落本地意图 |

首版取舍：**读 + 发 + 附件为主干；联系人只做本机通讯录 + 收件人历史；GAL 入口不暴露。**

## 5.1 ItemOperations 取正文的实测坑（2026-11-10）

三条与规范不一致、但实测确定的行为，改 `fetchBody` 前必读：

1. **`Options` 必须紧跟 `Store`，排在 `CollectionId` / `ServerId` 之前。** 按 MS-ASCMD 的顺序（`Store → CollectionId → ServerId → Options`）发，网关只回 `ItemOperations Status=2`（协议错误），响应体 13 字节；把 `Options` 提前即 `Status=1`。客户端已在契约测试里钉住这个顺序。
2. **`TruncationSize` 按字节算，且 `Truncated` 会误报。** 取 20000 时正文实际完整（结尾 `</html>`）却回 `Truncated=1`，导致每封信都要多跑一次全量请求；取 200000 且正文约 1 万字时不再置位。客户端默认用 200000，只有真置位时才免上限重取，且以「重取结果未置位」为准。
3. **`Body/Type` 可能是 1（纯文本）。** 同一封信问 `Type=2` 得到 2（HTML，约 1 万字符），问 `Type=1` 得到 1（纯文本约 1200 字符，`\r\n` 保留）。渲染前必须按返回的 `Type` 分支，纯文本要按 `pre-wrap` 排版，否则换行全丢。

旁证：WBXML 里同名标签跨页（`CollectionId` 在页 0/6/8），编码器必须**确定性地挑最低页**；否则 `Fetch` 内部切页会挑到页 8，同样回 `Status=2`。

## 5.2 Ping 实测：不支持长轮询（2026-11-09）

`Ping` 按 EAS 16.1 发 `HeartbeatInterval` = 15 / 60 / 300 秒，三档都在 0 秒内返回 `Status=4`——既不是「心跳超时」也不是「有变更」。调大间隔不会让它变成「有新邮件就立即返回」。**判定：本网关不支持长轮询**，不是 Ping 参数问题。

客户端行为：`EASClient.ping` 保留（复测用，CLI 未暴露子命令），App 不依赖它刷新，改为 **5 分钟轮询 `Sync`**（`UumailApp` 的 task 循环，间隔见 `CMP-APP/spec.md`；失败保留旧数据，下一轮再试）。UI 的刷新节奏按轮询如实标注，不承诺秒级推送。

## 5.3 Sync 信封返回 Cc（2026-11-14 实测）

- 用已登记设备对收件箱连续 `Sync`（首轮 `SyncKey=0` 只回新 key；第二轮取窗口内 25 封），`ApplicationData` 字段为 `To,Cc,From,Subject,DateReceived,DisplayTo,ThreadTopic,Importance,Read,Attachments,Body,MessageClass,InternetCPID,Flag,ContentClass,NativeBodyType,ConversationId,ConversationIndex,Categories,IsDraft`。
- 抽样前 3 封均含 `To` 与 `Cc`；`Cc` 是单个字符串，可含多个地址（观察长度 67–259 字符）。空/纯空白 `Cc` 按无值处理。
- 结论：REQ-0012 的 Cc 数据链路可直接从 Sync 信封取得，不需要 ItemOperations 逐封抓 MIME 头；`EASMessage.cc` 由 T-1114-02 落地。

## 6. 设备登记与失效处理

- 网关以 `DeviceId` 为键登记，状态「未激活」时**静默丢弃**请求：读命令回 `200` 空 body，写命令回 `401`。客户端必须把这两种现象都映射为「设备未登记」而不是「网络问题」或「密码错误」。
- **同一 DeviceId 疑似不能并发会话**：开发中 CLI 与应用同时用同一 ID 时，应用侧出现过 `deviceNotRegistered`，串行重试后恢复。未严格复现，按「同一设备 ID 同时只有一个客户端在跑」对待；排查时先关掉另一个客户端。
- 设备 ID 来源：优先用一台**已报废、仍在网关登记为激活**的旧手机 ID；不要复用在用手机的 ID，否则两边同步游标互相顶掉，手机会被迫全量重同步。
- 换机/清理后需要重新登记激活（公司侧通过短信指令查/删设备清单，具体指令问 IT）。
- 客户端与文档都不硬编码具体 ID；首次配置时在**高级设置**里手填，存 Keychain（T10）。

## 7. 诊断步骤

探针环境（`~/working/公网邮箱访问`）提供的命令行顺序，可作为 M1 落地前的排障参照：

1. `diagnose`：`OPTIONS` → `Provision` → `FolderSync` → `Sync` 一次跑通，打印协议版本与每步状态。
2. `folders`：确认收件箱 `Type=2` 的 `ServerId`。
3. `list`：按窗口取最新若干封，输出信封与截断正文。
4. `send`：发一封自测信，看 `http=200` 且 body 长度为 0。
5. 排障顺序：`444` → 查四参数；`200` 空 → 查设备激活；`502` 约 20s → 查 WBXML 字符串/opaque/额外元素；`401` → 区分认证与写命令设备未激活。

也可直接 `curl -X OPTIONS` 裸 URL 看 `MS-ASProtocolVersions` 与 `MS-ASCommands` 是否返回，判断网关是否对该设备放行。

## 8. 凭据与合规纪律

- 账号密码只在 `.env`（600）或 Keychain；不写入 README、日志、注释、commit。
- 抓包与 `output/`、`logs/` 不入库；样本必须脱敏（主题、正文、收件人、附件内容全部替换）。
- 本方案等价于「把 Mac 当成一台已登记的 iPhone」，走公司已开放的移动端官方通道，不涉及绕过认证。
- 若公司策略要求此类访问必须走 MDM/零信任客户端，先与 IT 确认合规性再长期使用；这也是 `plan/risks.md` R2 的触发条件。
