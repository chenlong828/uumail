---
layer: design
module: mail
status: designed
updated: 2026-11-20
flow: mail/read
scenario: SCN-0020
---

# SCN-0020 附件取用交互（双击打开、右键另存为）

**结果**：用户在阅读页看到附件条；**单击只选中**，**双击**（或聚焦后按 Return）在缓存未命中时自动
下载、命中时直接复用缓存，并用系统默认程序打开一次；**右键/Control-单击**出现系统菜单，至少含
「打开」「另存为…」；「打开」与双击等效，「另存为…」把副本写到用户选择的位置并保留缓存文件；
下载/另存为失败给出用户可见、可重试的提示，且不打开不存在的文件。缓存仍按 2 GB、修改时间最旧优先
清理，只删缓存文件，不删邮件/正文/附件元数据；内联图片自动下载/显示不受影响（`SCN-0019` 只回归）。

## 入口

- `CMP-APP#AttachmentStripView`（新，internal；单击选中、双击/Return、`.contextMenu`、选中态、AX 动作、
  错误 banner）与 `CMP-APP#MessageBodyView` 的附件条接线。
- `CMP-APP#MailboxView` 的接线 + `CMP-APP#AttachmentActionModel`（`open`/`startSave`/`syncSelection`/
  `visibleSavingID`；APP 动作代际 `epoch`）+ `CMP-APP#AttachmentExport`
  （`SavePanelPresenting`/`SystemSavePanel`/`AttachmentFileCopy`/`AttachmentSaveFlow`/`AttachmentActionGate`）。
- `CMP-PRES#MailboxViewModel.download`、`#attachmentErrorText`（只读；2026-11-20 P2 additive 公开面
  已人工确认 A，记录 `history/decisions/2026-11-20-attachment-error-surface.md`）。
- `CMP-SCN-READ#downloadAttachment`（不改；缓存命中/单飞/fetch/store/mark）。
- `CMP-DOMAIN#AttachmentFiles`（生产 `FileAttachmentFiles`）与 `CMP-STORE#markAttachmentCached`（不改）。

## 运行序

流程 `F-READ-09`：

1. 阅读页按附件元数据（名称、大小、`fileReference`）渲染附件条；无选中邮件时不渲染。
2. 单击附件：只选中（可见描边），**0 网关、0 打开**；Space 同样只选中。
3. 双击附件（或聚焦后 Return）：
   1. `ReadScene.downloadAttachment` 先查 `AttachmentFiles.cachedURL`；命中直接返回缓存 URL；
   2. 未命中 → 按 `fileReference` 单飞 → `MailGateway.fetchAttachment` 一次 → `AttachmentFiles.store`
      原子写（内含 2 GB 最旧优先 prune）→ `MailStore.markAttachmentCached` → 返回 URL；
   3. 下载完成后再 `NSWorkspace.shared.open(url)` 一次；失败不打开。下载返回后、打开前比较发起动作的
      `selectedListKey` 与 APP 动作代际（`AttachmentActionModel.epoch`）；缓存文件缺失时只在代际仍当前时
      重下一次，仍缺失则不打开。
4. 右键/Control-单击 → 系统菜单「打开」「另存为…」：
   - 「打开」= 第 3 步；
   - 「另存为…」→ 先按第 3 步取得缓存 URL（不打开）→ 比较发起动作的 key/APP 动作代际 →
     `NSSavePanel` 选目标 → **主线程只等待**；
     复制在后台任务完成（`AttachmentFileCopy.copy` 为 `nonisolated async`，分块复制并检查取消），
     先写目标目录下的临时文件，成功后原子替换/移动到目标 → 缓存文件保留；面板取消不改状态、不报错；
   - 复制期间附件条下显示「正在另存为…」与「取消」；UI 主线程不被复制占用。取消只清理临时文件，
     目标不变、不报错。**下载阶段不显示「取消」**（取消入口只在面板/复制阶段）；
   - 面板后、复制前再次比较发起动作的 key/代际与取消状态；不一致则不复制、不写文案。
5. 失败路径：
   - 下载失败/离线/限流 → 不打开；`attachmentErrorText` 显示 `ErrorText` 文案；再次双击/Return 即重试；
   - 另存为失败（目标不可写/磁盘满/复制失败）→ 不丢失缓存；`saveErrorText` 显示 `ErrorText` 文案（如「本地存储失败：…」）；
   - 缓存文件被外部删除或 `cache_path` 悬空 → `cachedURL` 未命中 → 重新下载，不打开缺失文件；
   - 面板/复制期间源缓存被另一次 `store` 的 prune 删除 → **不自动重下**；`saveErrorText` 显示
     「附件缓存已失效，请重试另存为」；重试入口 = 再次「另存为…」（重新下载）；不把保存重试错误写进
     `attachmentErrorText`；
   - 目标与源相同 → no-op，不破坏缓存；目标不存在 → 临时文件原子移动到目标；目标已存在且面板确认覆盖 →
     原子替换为目标字节；复制失败/取消 → 临时文件清理，目标保持原样（不产生半文件）；
   - **迟到结果**：VM 的 `download` 捕获 `selectionGeneration` + `selectedListKey`；APP 的
     `open`/`save` 捕获 `AttachmentActionModel.Origin(key, epoch)`（`epoch` 在 `selectedListKey` 真正
     变化时递增）。`await` 回来后若选择/代际已变化：不写 `attachmentErrorText`/`saveErrorText`、
     不打开、不弹窗、不清新邮件的错误；A→B→A 也按 APP 代际丢弃旧结果；APP 不读 `Presentation` 的
     internal `selectionGeneration`。
   - **取消**（取消入口只在面板/复制阶段；下载阶段不显示「取消」）：面板/复制阶段取消 → 不复制、
     清理临时文件、目标不变、不写错误、不打开。下载阶段任务被取消（窗口关闭/上层取消）→ 不弹面板、
     不复制、不写错误、不打开；**已在飞的共享下载不中止**（`FlightBoard` 不随调用方取消），完成后由
     取消方丢弃结果。
6. 并发：同一附件的重复双击/打开共享一次下载（`FlightBoard` 单飞）；另存为同一时刻只有一个保存
   流程（`saveTask` 全局单飞，进行中的重复触发被忽略）；`AttachmentActionGate` 保证只打开一次、
   只弹一个保存面板；不产生重复文件/重复弹窗；下载与复制都不得占用主线程。
7. 内联图片（`SCN-0019`）、正文/CSP/远程开关/字号/白底不进入本流程，零改动。

## 失败路径

- **下载失败**：`download` 返回 nil，写 `attachmentErrorText`；不调用 opener；重试入口 = 再次双击/
  Return/右键「打开」；不做自动无限重试。
- **另存为失败**：`AttachmentFileCopy` 抛 `MailError.storage`；临时文件清理；缓存保留；
  `saveErrorText` 可见；重试入口 = 再次右键「另存为…」。
- **复制取消**：复制中取消 → 临时文件清理、目标不变、不写错误文案、不打开。
- **目标不存在 / 已存在**：不存在 → 临时文件原子移动到目标（不用 `replaceItemAt` 的空目标前提）；
  已存在且面板确认覆盖 → 原子替换；目标不可写/磁盘满 → 失败、临时文件清理、缓存保留。
- **迟到结果（状态隔离）**：`download` 在 VM 内捕获发起时的 `selectedListKey` 与
  `selectionGeneration`（internal）；`open`/`save` 在 APP 内捕获 `Origin(key, epoch)`，`epoch` 在
  `selectedListKey` 真正变化时递增；`await` 回来后先比较当前选择/代际，不一致则不写
  `attachmentErrorText`/`saveErrorText`、不打开、不弹窗、不清新邮件的错误；A→B→A 也按 APP 代际丢弃；
  单飞 gate 只防重复动作，不替代该 guard。
- **面板取消**：面板返回 nil；不复制、不报错、不改缓存/选择。
- **源缺失**：面板前/复制中源不存在 → **不自动重下**；`saveErrorText` = 「附件缓存已失效，请重试另存为」；
  不打开缺失文件；重试入口 = 再次「另存为…」（重新下载）。保存重试错误不写 `attachmentErrorText`。
- **并发双击**：gate 第二次直接返回；下载共享；只打开一次。
- **单击/Space**：0 网关、0 打开；只改选中态。
- **缓存清理**：prune 只删缓存目录文件；邮件/正文/附件元数据不被清理；被删附件再打开可重下。
- **无选中邮件**：附件条不渲染；`download` 返回 nil，不写错误文案。
- **打开前文件消失**：下载成功到 `NSWorkspace.open` 之间缓存可能被 prune；打开前 `fileExists` 检查，
  仅在发起动作的 key/APP 代际仍当前时重下一次；仍缺失或代际已变则不打开、不崩溃。

## 不可变引用

- **`SCN-0005` 的下载原语**：缓存目录/确定性文件名 `<sha256前16>-<safe name>`、原子写、2 GB 总上限、
  修改时间最旧优先、每次 `store` 后 prune、同一 `fileReference` 单飞、先落盘再 `markAttachmentCached`；
  `cachedURL` 只判存在、不 touch mtime。
- **`SCN-0005` 的既有欠账**：25MB 上限、断点续传、`AttachmentName` 回退**不在本场景验收内**，仍归
  `SCN-0005`，不假装实现、不删其测试/状态。
- **`SCN-0019`**：内联图片自动下载/显示、只取正文实际引用、20MB guard、失败跳过；本场景只回归，
  不重开、不改断言。其边界段引用的旧「附件条点击=下载/打开」由 `REQ-0026` 取代，见 §与相邻场景的边界。
- **`SCN-0013`/`SCN-0018`**：远程开关、CSP 两档、ATS 载体；本场景不改正文渲染/网络门控。
- **`SCN-0004`**：正文阅读/补拉/脚本不执行；本场景不改正文。
- **`SCN-0015`/`SCN-0010`**：字号档位/白底；附件条在档位下仍可操作、不溢出。
- **数据/契约**：`attachments` schema、`MailDomain.Attachment`/`AttachmentRef`/`AttachmentFiles`、
  `MailGateway`、EAS 命令形状均不改；本场景不新增 schema/列/缓存策略。
- **真实数据脱敏**：真实邮件/附件只做发布前冒烟；自动化用假附件名/假字节，不写真实主题/发件人/
  地址/账号/路径。

## 测试

| ID | 类型 | 层级 | 方案 |
|---|---|---|---|
| `T-SCN-0020-01` | 正 | L1（VM/场景）+ L2（附件条双击） | 假附件 A、缓存为空：双击一次 → `fetchAttachment` 1 次、`store`/`markAttachmentCached` 1 次、打开器收到 URL 1 次；再双击 → 0 网关、打开器 1 次；并发双击 → 1 次下载、1 次打开；gate 第二次返回 false。 |
| `T-SCN-0020-02` | 正 | L2（菜单/保存流/复制） | 已缓存附件 B：`view.menu(for:)` 项恰为「打开」「另存为…」；`performActionForItem(0)` → 0 网关、打开器 1 次（fake opener）；`(1)` + fake panel 选目标 → 目标字节 = 缓存字节、缓存仍在；面板取消 → 0 复制、0 报错；复制失败 → 文案、缓存仍在；**面板前后源缺失 → 「附件缓存已失效，请重试另存为」、0 重下/0 复制**。 |
| `T-SCN-0020-03` | 正 | L1（缓存/场景）+ L2（打开旧附件） | 用 `FileAttachmentFiles(directory:maxBytes:)` 的可配置小上限（如 64 KB，**不真写 2 GB**）写入新附件 C 触发 prune：按修改时间最旧优先删文件；C 可按命中取用；被清理的旧附件 D 再打开 → 按未命中重下 1 次；邮件/正文/附件元数据仍在；无重复副本/半文件；缓存文件被外部删除 → 重下、不打开缺失文件。 |
| `T-SCN-0020-04` | 反 | L1（失败/单飞/单击分支）+ L2（附件条） | ① 网关失败/离线 → 不打开、`attachmentErrorText` 非空、可重试；② 另存为目标不可写 → 文案、缓存不丢；③ 缓存外部删除后双击 → 重下；④ 单击/Space → 0 网关、0 打开；⑤ 下载中重复双击 → 共享 1 次下载、只打开 1 次、无重复弹窗；⑥ 面板/复制期间源被 prune → 不自动重下、`saveErrorText` 可重试；⑦ 下载阶段任务被取消 → 不弹面板、不写错误（`01g`/`10d`）。 |
| `T-SCN-0020-05` | 回归 | L2（生产 `MessageWebView`/`InlineImageHTML`） | **A1/`SCN-0019`**：复跑 `InlineImageVerifyProbe`（源码/命令见 §测试载体）：`cid:` 图 `naturalWidth>0`、快照非白/品红像素 >0、`requests=0`；远程默认关 0 请求；生产改写串渲染；失败保留文字；负控制 raw `cid:` 被 CSP 阻止。 |
| `T-SCN-0020-06` | 回归 | L2（生产 `MessageBodyView` 接线） | **生产 `MessageBodyView` 的 `natural`（100/120/145%）与 `capped`（175/225%）两处都渲染 `AttachmentStripView`**：单击 0 `onOpen`/0 下载；双击 1 次 `onOpen`；菜单项恰为「打开」「另存为…」；`errorText != nil` 才出现 banner；无错误时附件条高度与改造前一致；两分支均不裁剪/不挤压正文视口。 |
| `T-SCN-0020-07` | 回归 | L2（既有探针复跑/等价断言） | **A8**：`SCN-0013`/`SCN-0018` CSP 两档与远程 gate（阻挡档 0 请求、放行档仅 fixture 请求、生产 `MessageBodyView` 正文无独立开关行）；`SCN-0010` 深色外观下白底（floor RGB ≥250）；`SCN-0015` 五档字号下 `MessageBodyView` 仍渲染附件条、正文视口 273/242.5/205/259/259（±1）、不重叠/不裁剪。 |
| `T-SCN-0020-08` | 正（B4 质量） | L2（生产 `AttachmentExport` + 慢/大文件替身） | `AttachmentSaveFlow` 的 `copy` 在非主线程执行；350ms 慢复制期间主线程 heartbeat 持续推进（≥10 tick）；生产 `AttachmentFileCopy.copy` + 64 MiB 文件复跑至少 1 tick；目标字节=缓存字节；取消/失败清理临时文件、目标不变；目标不存在用原子移动、已存在用原子替换；源==目标 no-op。 |
| `T-SCN-0020-09` | 反（B3 质量） | L1 + L2 | VM 侧：A 下载在飞 → 切到 B → A 迟到失败/成功：B 的 `attachmentErrorText` 不被写或清；A 成功也不打开 A 的文件；A→B→A 代际变化时旧结果仍丢弃；当前选中的失败仍正常显示。 |
| `T-SCN-0020-10` | 反（B1 质量） | L2（生产 `AttachmentActionModel`/`AttachmentSaveFlow` + fake download/panel/copy） | APP 动作代际：`10a` 打开前文件缺失且切 B/A→B→A → 不重下、不打开；origin 仍当前 → 重下 1 次并打开。`10b` 面板期间 A→B→A → 面板后 `shouldContinue=false`：0 复制、`saveErrorText` nil、`visibleSavingID` nil。`10c` 复制失败 → `saveErrorText` 非空；切 B → 清空、B 不显示 A 的文案。`10d` 下载阶段取消 → 0 面板/0 复制/不写文案，已在飞下载仍完成。`10e` 复制中切 B → 无第二次 `download`（无 `reResolve`）、旧结果丢弃、目标字节正确。 |

> `T-SCN-0020-01..04` 仍是本场景的 3 正 1 反；`05..10` 是评审 B1–B4 要求补的回归/接线/质量用例，
> 不改变场景结果与 3 正 1 反结构。`T-SCN-0020-05..07` 只回归既有 `verified` 场景断言，不新增 L3/L4。

**证据层级与限制**：

- L1：`PresentationTests`（`MailboxViewModelAttachmentTests`）、`ScenesTests`（`ReadSceneTests` 缓存/单飞/
  外部删除）、`CompositionTests` 无新增；不触网。
- L2：直接编译生产 `AttachmentStripView.swift`、`AttachmentExport.swift`、`MessageBodyView.swift`/
  `MessageWebView`/`MessageBodyStyle.swift` 与所需 `Presentation` 对象，用 fake panel/copy/opener 断言；
  源码/命令/原始输出入 `task-spaces/<run>/evidence/attachment-access-verify/`。
  - `T-SCN-0020-05`：复用 `task-spaces/20261120-111818/evidence/inline-image-verify/InlineImageVerifyProbe.swift`
    （17 用例，生产 `InlineImageHTML` + 生产 `MessageBodyView`/`MessageWebView`）对当前 HEAD 重编译/复跑；
    `swiftc` 文件列表**必须含** `Sources/uumail/AttachmentStripView.swift`；先编译（exit 0）再运行；
    原始输出 `l2-inline-image-build.txt`、`l2-inline-image-regression.txt`，命令 `commands.md`。
  - `T-SCN-0020-06`：新增 `AttachmentWiringProbe`（生产 `MessageBodyView` + `AttachmentStripView`，离屏
    `NSHostingView`/`NSWindow`；`natural`/`capped` 两分支、五档字号；读 `NSView.menu(for:)`、合成单击/双击、
    读 banner 文本）；原始输出 `l2-wiring.txt`。
  - `T-SCN-0020-07`：`RemoteContentBodyProbe`/`RemoteImageProbe`/`AppearanceProbe`/`FontSizeProbe` 的
    既有断言复跑或等价断言；若归档探针源不可用，按 `CMP-APP` 规格 2026-11-16/17 与 `SCN-0018` 的记录
    在新探针中实现等价断言，不得静默跳过；原始输出 `l2-regression-*.txt`。
  - `T-SCN-0020-08`：`AttachmentExportProbe`（生产 `AttachmentSaveFlow`/`AttachmentFileCopy` + 慢 copy/
    大文件替身 + 主线程 heartbeat + 取消）；原始输出 `l2-async-copy.txt`。
  - `T-SCN-0020-09`：L1 `MailboxViewModelAttachmentTests` 的迟到结果/取消用例 + L2 banner 不串台；
    原始输出 `l1-vm-stale.txt`、`l2-stale-banner.txt`。
  - `T-SCN-0020-10`：`AttachmentActionProbe`（生产 `AttachmentActionModel`/`AttachmentSaveFlow` + fake
    download/panel/copy/opener，直接驱动 `syncSelection`）；原始输出 `l2-action-guard.txt`。
- **不上 L3/L4**；真实右键/Control-单击菜单弹出、真实 `NSSavePanel`、VoiceOver 自定义动作、选中态/
  banner 像素为发布前手工冒烟残余，不写成自动化通过。
- `SCN-0019` 的 A5 真样本冒烟仍为发布前/人工项；不在本场景执行。

## 状态

`designed`（2026-11-20 设计落卡；**第 2 轮按方案评审 `review.md` B1–B4 修订**；
**第 3 轮按 `review2.md` B1–B3 修订：APP 动作代际、N3/源缺失 guard、取消收窄、T-05 编译文件**；
未实现、未验证）。实现完成后由收尾在评审 pass 时统一翻 `verified`；本节点不翻状态位。

- 实现：待 task-split 拆任务；不改 `Sources/`（本节点）。
- 未实现项：本场景 01–10 全部待实现；`SCN-0005` 的 25MB/续传/名称回退仍为其欠账，不在本场景。
- 设计依据：`task-spaces/20261120-160446/design3.md` §4/§6（第 3 轮；第 2 轮见 `design2.md`）；
  公开面确认 `history/decisions/2026-11-20-attachment-error-surface.md`；B1 取代口径见 §与相邻场景的边界。

## 与相邻场景的边界

- **与 `SCN-0005`**：`SCN-0005` 拥有下载原语（缓存/单飞/2 GB/mark）与其 25MB/续传/名称回退欠账；
  本场景拥有用户取用交互（单击/双击/右键/另存为/失败可见）与打开/保存的用户可观察结果。本场景
  把 `SCN-0005` 的缓存/单飞/prune 作为不可变引用，不新增缓存策略断言；不删/不改 `SCN-0005` 的欠账、
  测试与状态。
- **与 `SCN-0019`（取代关系，2026-11-20 第 2 轮）**：`REQ-0026`（`accepted`）D2/A7 的「单击只选中、
  双击/右键打开」**取代** `SCN-0019` 边界/不可变引用段中「附件条点击=下载/打开、归 `SCN-0005`」的旧交互
  口径。取代范围仅限「附件条单击取用入口」；`SCN-0019` 自身 `T-SCN-0019-01..04`（内联图片自动取用/渲染/
  失败降级）与 `verified` 状态不变，本卡不编辑 `SCN-0019`；`SCN-0005` 仍拥有下载原语/缓存与 25MB/续传/
  名称回退欠账，其入口由本卡定义。`REQ-0026` A8 的「`SCN-0019` 回归」= 其自身 3 正 1 反，不含旧点击口径。
- **与 `SCN-0013`/`SCN-0018`**：远程开关/CSP/ATS 归它们；本场景只要求打开附件不改变正文渲染/网络门控。
- **与 `SCN-0004`**：正文基本渲染/补拉/脚本不执行归它；本场景不改正文。
- **与 `SCN-0015`/`SCN-0010`**：字号/白底归它们；本场景只要求附件条在各档位下仍可操作、不溢出。
- **与 `REQ-0026`**：验收 = 本场景 01–04 + `T-05..10`（A1/A8 回归、生产接线、异步复制、迟到结果、APP 动作代际/取消）+ `SCN-0019` 回归；`REQ-0005`/`SCN-0005` 状态不变。
