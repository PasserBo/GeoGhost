# Tasks: add-reporting-and-blocking

## Now
等待开始；可以在 add-publishing 完成后与 add-explore-map 并行。

- [ ] T1 delta `content-safety` + 举报原因列表 — owner: agent 起草 · me 确认 · verify: check-delta 无错误 + 用户确认
- [ ] T2 举报界面 — owner: agent · after: T1 · verify: 模拟器
- [ ] T3 屏蔽 / 解除屏蔽；设置中的屏蔽列表 — owner: agent · after: T1 · verify: 模拟器
- [ ] T4 审核手册：待审核与被举报内容的查询、通过 / 隐藏 / 封禁的 SQL — owner: agent · verify: 本地 SQL 测试
- [ ] T5 新举报与待审核的开发者通知 — owner: agent · verify: 触发一次测试通知
- [ ] T6 确认能在 24 小时内处理（通知到手机、手册可用） — owner: me · after: T4, T5 · verify: 演练一次
