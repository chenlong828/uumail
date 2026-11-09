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
swift build
swift test
```

原始协议探针（Python）留在 `~/working/公网邮箱访问`，只作证据，不是本仓库的一部分。
