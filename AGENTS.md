# 项目约定（uumail）

## 文档根

`doc/` 是文档根：`requirements/`、`plan/`、`design/`、`works/`、`history/` 都相对 `doc/` 解析；仓库根引用时加 `doc/` 前缀。导航见 `doc/README.md`。

## 构建与测试

本机 file sandbox 会拦 `~/Library` 缓存与 SwiftPM 的嵌套 sandbox，所以一律用包装脚本：

```bash
./Scripts/swiftw build
./Scripts/swiftw test
```

不要直接用 `swift build` / `swift test`（会因 clang 模块缓存写到工作区外被拒）。

## 发布

**每个开发里程碑完成后**，运行：

```bash
./Scripts/make-app.sh
```

它做 release 构建、组装 `dist/uumail.app`、ad-hoc 签名，并写 `dist/build-info.txt`（commit / 时间）。`dist/uumail.app` 是构建产物，不入库。

## 凭据与首次配置

账号密码只走 Keychain 或运行时环境变量；`.env`、`logs/`、`output/`、`dist/uumail.app/` 均已 gitignore。

首次配置有两种方式：

1. 打开 `dist/uumail.app`，在配置页手填（推荐给用户）。
2. 开发机免配置：在探针目录加载 `.env` 后运行 `uumailctl seed`，把账号写进登录 Keychain；之后 `dist/uumail.app` 启动即自动同步。删除用
   `security delete-generic-password -s com.uumail.account`。

应用数据在 `~/Library/Application Support/uumail/mail.sqlite`，不在 `dist/`。

## 提交

一个任务一个 commit，message 末尾带 `T-` 与 `SCN-` 标识。
