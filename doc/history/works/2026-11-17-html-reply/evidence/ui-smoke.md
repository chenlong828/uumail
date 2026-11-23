# SCN-0016 L2 UI 冒烟（2026-11-17）

目的：在没有 AX 权限的会话里，用真实 App + 真实邮件验证撰写 sheet 的可见形态与宽度。

方法：临时在 `MailboxView` 加一个只读环境触发的预览钩子（验证后已移除，`git diff` 无残留），build `dist/uumail.app`，打开真实 App，等待 sheet 出现，用 `CGWindowListCopyWindowInfo` 读窗口 bounds，`screencapture` 取图。

结果：

- 主窗口：`1920×987` @ `(0,30)` points（窗口名「收件箱」）。
- 撰写 sheet：`1441×820` @ `(240,113)` points。
- 阅读窗格（detail 列）宽 = 1920 − (侧栏+列表 480) = **1440**；sheet 宽 **1441**（1pt 取整），即与阅读窗格等宽；sheet 水平居中于窗口 `(1920−1441)/2 = 239.5 ≈ 240`。
- 可见：标题「回复」、右上 `xmark`、收件人/抄送/主题字段、格式栏（B/I/U/S、字号、对齐、列表、清除）、底部「取消」「存草稿」「发送」、引文抬头（日期 + 发件人 + 写道：）、原邮件全宽正文、编辑器顶部空行与光标。
- 未做：点击取消/发送、拖拽窗口、窄窗格（<480）布局；这些由 L1 `hasEdits`/`ComposeDocument` 测试与代码分支覆盖，未冒充 L2。

限制：当前 shell 无 Accessibility（`AXIsProcessTrusted() == false`），无法自动化点击；截图为人工读取。截图不入库（含真实邮件内容），仅本目录保留。
