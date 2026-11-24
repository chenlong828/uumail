# W-M3-16 结果（2026-11-24）

- 结论：W-M3-16 完成；`REQ-0029`/`REQ-0030` `delivered`、`SCN-0024`/`SCN-0023` `verified`；`T-1124-01`…`T-1124-15` 全部完成。
- 实现提交：`a3f4a05`（WAL + outbox 拆分）、`527ce9f`（EAS 解析）、`563f354`（领域值/展开/ICS）、后续 adapter/store/scene/PRES/APP/ROOT 提交。
- 验证：`./Scripts/swiftw test` → **437 tests / 71 suites**；`bash Scripts/check-architecture.sh` → 4/4；
  `./Scripts/make-app.sh` → release 构建成功（`dist/uumail.app`）。
- 场景证据：`Tests/PresentationTests/CalendarScenarioTests.swift` 的 `T-SCN-0023-01..04` / `T-SCN-0024-01..04`。
- 遗留（登记，不在本批）：月/周像素与 `NSWorkspace` 导入的发布前人工冒烟；`W-REFACTOR-02`（账号/文件夹拆分）未立项；
  R56/R58 为已接受限制，R61（WAL 副文件备份）仍开放。
