# uumail

macOS 原生邮件客户端，只走 Exchange ActiveSync（以「一台已登记的 iPhone」身份接入公司 Exchange）。

## 状态

设计已冻结（P1，见 [`doc/design/architecture.md`](doc/design/architecture.md)），协议已用真实网关验证（[`doc/design/components/CMP-EAS/playbook.md`](doc/design/components/CMP-EAS/playbook.md)）。代码正在开发中，首个工序是账号接入与设备身份。

## 结构

```
Package.swift        Swift 6 包（EASClient / MailStore / uumailctl）
Sources/             代码
Tests/               测试
doc/                 文档根（需求、计划、设计、工序、历史五态）
```

## 文档入口

[`doc/README.md`](doc/README.md) —— 阅读顺序与当前状态。文档树内路径均相对 `doc/`。

## 构建与测试

```bash
./Scripts/swiftw build
./Scripts/swiftw test
./Scripts/swiftw run uumailctl diagnose
./Scripts/make-app.sh && open .build/uumail.app   # 图形界面
```

`Scripts/swiftw` 只是把三件本机必须的事包起来：SwiftPM 缓存放进 `.build/`、关闭嵌套 sandbox、固定 scratch 路径。直接用 `swift build` 会让 clang 模块缓存写到工作区外而被拒。

## 真机验证（只读）

凭据不落在本仓库，运行时从探针目录注入：

```bash
set -a; . ~/working/公网邮箱访问/.env; set +a
export EAS_HOST EAS_USER EAS_PASS EAS_DOMAIN EAS_DEVICE_ID
./Scripts/swiftw run uumailctl diagnose
./Scripts/make-app.sh && open .build/uumail.app   # 图形界面
```

`diagnose` 只发 `OPTIONS → Provision → FolderSync`，不改服务器数据。

原始协议探针（Python）留在 `~/working/公网邮箱访问`，只作证据，不是本仓库的一部分。
