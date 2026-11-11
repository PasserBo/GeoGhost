# Tasks: add-likes-and-saves

## Now
等待 add-explore-map 的详情页（T5）。

- [ ] T1 delta `reactions` — owner: agent · verify: check-delta 无错误 + 用户确认
- [ ] T2 决定灵感夹入口 — owner: me · verify: proposal Decisions
- [ ] T3 点赞 / 取消（立即生效，被拒绝时恢复并说明） — owner: agent · after: T1, add-explore-map T5 · verify: 单元测试 + 模拟器
- [ ] T4 灵感夹：加入 / 移出 / 列表 / 上限提示 / 已撤回贴纸的显示 — owner: agent · after: T1, T2 · verify: 单元测试 + 模拟器
