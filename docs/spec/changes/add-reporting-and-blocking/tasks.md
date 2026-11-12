# Tasks: add-reporting-and-blocking

## Now
2026-11-12：T1 已确认；举报后对举报人立即隐藏已加（T7）；3 人举报改为暂时隐藏并重新审核（T8）。**需要用户在 Supabase SQL Editor 依次执行迁移 `20261112020000_hide_reported_from_reporter.sql`、`20261112030000_report_hide_is_rereview.sql`**；T2、T3 已实现并有单元测试，待模拟器走查（需要一张别人的公开贴纸）。下一步：用第二个访客发布一张贴纸并在审核台通过，然后在模拟器走查举报、屏蔽、解除屏蔽（T2/T3）→ T4 审核手册。T5 通知**不要做**，等讨论。

- [x] T1 delta `content-safety` + 举报原因列表 — owner: agent 起草 · me 确认 · verify: check-delta 无错误 + 用户确认 · done 2026-11-12
  - evidence: `specs/content-safety/spec.md` check-delta 无错误；用户 2026-11-12 确认原因列表与入口（proposal Decisions）
- [ ] T2 举报界面 — owner: agent · after: T1 · verify: 模拟器
  - 2026-11-12 已实现：`Features/Online/SafetyViews.swift` `ReportSheet`，入口在 `RemotePostSheet` 的「更多」菜单；`Services/Safety/SafetyClient.swift`。单元测试通过：`ReportDraftTests`、`SafetyClientTests.testReportSendsReasonAndNote`、`testDailyReportLimitIsARefusal`。模拟器走查未做：后端目前没有别人的公开贴纸（需要第二个访客发布一张并审核通过）。
- [ ] T3 屏蔽 / 解除屏蔽；设置中的屏蔽列表 — owner: agent · after: T1 · verify: 模拟器
  - 2026-11-12 已实现：详情「更多」→ 屏蔽（确认后关闭详情，世界地图立即去掉该作者并重新拉取）；设置 → 线上 → 已屏蔽的用户（`BlockedUsersView`，解除屏蔽、空状态、加载失败重试；没有身份时不创建访客）。单元测试通过：`SafetyClientTests`（block/unblock/blockedUsers ×4）、`ExploreBlockingTests`。模拟器（GeoGhost Shots）：设置 → 线上 → 已屏蔽的用户 显示空状态 ✓。屏蔽 / 解除屏蔽的走查未做：后端目前没有别人的公开贴纸。
- [ ] T7 举报后对举报人立即隐藏（审核指南 1.2）— owner: agent（代码）· me（在 SQL Editor 执行迁移）· verify: SQL 测试 + 单元测试 + 迁移已在线上执行
  - 2026-11-12 agent 部分完成：delta「举报后自己不再看到」；迁移 `server/supabase/migrations/20261112020000_hide_reported_from_reporter.sql`；SQL 测试 `55_reported_hidden_from_reporter.sql` 10 条通过（全套 204 条通过）；客户端举报成功后显示「不会再看到」确认，关闭详情并从地图移除（`ExploreReportingTests`）。Worker 33/33、admin 16/16 测试通过。待用户执行迁移。
- [ ] T8 多人举报后暂时隐藏并重新审核 — owner: agent（代码）· me（在 SQL Editor 执行迁移）· verify: SQL / admin / 单元测试 + 迁移已在线上执行
  - 2026-11-12 agent 部分完成：迁移 `server/supabase/migrations/20261112030000_report_hide_is_rereview.sql`（自动隐藏 → `pending` 并保留 `published_at`；重新审核通过不重复计入 `approved_count`；`admin_stats` 等待时间从第一条举报算起；「保留」公开帖会关闭举报——修复此前不会关闭的问题；旧的自动隐藏帖移回审核）。SQL `56_report_hide_is_rereview.sql` 18 条通过，全套 222 条通过；审核台标「重新审核」（admin 17/17）；App 显示「审核中」+ 重新审核说明（`ArtworkPublisherTests.testPostPutBackIntoReviewAfterReportsIsInReReview`，单元测试全部通过）；Worker 33/33。待用户执行迁移。
- [ ] T4 审核手册：待审核与被举报内容的查询、通过 / 隐藏 / 封禁的 SQL — owner: agent · verify: 本地 SQL 测试
- [ ] T5 通知 — owner: me + agent · verify: 讨论后定
  - 2026-11-12 **先不做**：用户希望打开 App 时弹窗、并能查看过去的通知，但要先讨论是否合适。
- [ ] T6 确认能在 24 小时内处理（通知到手机、手册可用） — owner: me · after: T4, T5 · verify: 演练一次
