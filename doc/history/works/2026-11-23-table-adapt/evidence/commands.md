# 证据复跑命令（2026-11-23）

## L2 表格布局探针

```bash
swiftc -module-cache-path /tmp/uumail-mcache \
  -Xcc -fmodules-cache-path=/tmp/uumail-mcache \
  Sources/uumail/MessageBodyStyle.swift \
  doc/history/works/2026-11-23-table-adapt/evidence/table-layout-probe/main.swift \
  -o /tmp/TableLayoutProbe
/tmp/TableLayoutProbe | tee doc/history/works/2026-11-23-table-adapt/evidence/table-layout.txt
```

## 真实样本（只读本机缓存正文，不提交正文/附件）

真实样本探针为临时 WKWebView 程序（`/tmp/probe`），加载本机 `mail.sqlite` 中该封邮件经 `InlineImageHTML`
改写后的正文，视口 1174pt、`pageZoom` 1.2/1.45/1.75/2.25，读取 `document.documentElement.scrollWidth` 与
`document.querySelectorAll('table')` 的宽度；输出见 `real-sample-table.txt`。不记录主题、发件人、正文、URL 或账号。

## 单元测试/门禁

```bash
./Scripts/swiftw test --filter InlineImageHTMLTests
./Scripts/swiftw test --filter MailboxViewModelInlineImageTests
./Scripts/swiftw test
./Scripts/swiftw test --no-parallel
bash Scripts/check-architecture.sh
./Scripts/make-app.sh
```
