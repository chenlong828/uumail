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

## 凭据

账号密码只走 Keychain 或运行时环境变量；`.env`、`logs/`、`output/`、`dist/uumail.app/` 均已 gitignore。真机验证用 `UUMAIL_DEBUG_ENV=1`（仅 DEBUG 构建）从环境注入，不写 Keychain。

## 提交

一个任务一个 commit，message 末尾带 `T-` 与 `SCN-` 标识。
