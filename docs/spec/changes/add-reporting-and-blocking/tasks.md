# Tasks: add-reporting-and-blocking

## Now
2026-11-12：T1 delta 已起草（待用户确认原因列表与入口位置，见 proposal Decisions）；T2、T3 已实现并有单元测试，待模拟器走查（需要一张别人的公开贴纸）。下一步：用户确认 T1 → 模拟器走查 T2/T3 → T4 审核手册。T5 通知**不要做**，等讨论。

- [ ] T1 delta `content-safety` + 举报原因列表 — owner: agent 起草 · me 确认 · verify: check-delta 无错误 + 用户确认
  - 2026-11-12 agent 部分：`specs/content-safety/spec.md` 已写，`spec_tool.py check-delta` 无错误；等待用户确认。
- [ ] T2 举报界面 — owner: agent · after: T1 · verify: 模拟器
  - 2026-11-12 已实现：`Features/Online/SafetyViews.swift` `ReportSheet`，入口在 `RemotePostSheet` 的「更多」菜单；`Services/Safety/SafetyClient.swift`。单元测试通过：`ReportDraftTests`、`SafetyClientTests.testReportSendsReasonAndNote`、`testDailyReportLimitIsARefusal`。模拟器走查未做。
- [ ] T3 屏蔽 / 解除屏蔽；设置中的屏蔽列表 — owner: agent · after: T1 · verify: 模拟器
  - 2026-11-12 已实现：详情「更多」→ 屏蔽（确认后关闭详情，世界地图立即去掉该作者并重新拉取）；设置 → 线上 → 已屏蔽的用户（`BlockedUsersView`，解除屏蔽、空状态、加载失败重试；没有身份时不创建访客）。单元测试通过：`SafetyClientTests`（block/unblock/blockedUsers ×4）、`ExploreBlockingTests`。模拟器走查未做。
- [ ] T4 审核手册：待审核与被举报内容的查询、通过 / 隐藏 / 封禁的 SQL — owner: agent · verify: 本地 SQL 测试
- [ ] T5 通知 — owner: me + agent · verify: 讨论后定
  - 2026-11-12 **先不做**：用户希望打开 App 时弹窗、并能查看过去的通知，但要先讨论是否合适。
- [ ] T6 确认能在 24 小时内处理（通知到手机、手册可用） — owner: me · after: T4, T5 · verify: 演练一次
