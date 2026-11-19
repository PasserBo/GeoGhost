# Tasks: prepare-ugc-release

## Now
文案全部起草完（隐私政策、社区规则、支持页、隐私标签、年龄分级、审核备注）。等 me 确认；页面要合并到 main 后才会发布。

- [ ] T1 隐私政策更新稿 — owner: agent 起草 · me 确认 · verify: 用户确认
  - 2026-11-12 草稿：`docs/privacy.md` 已更新并单独提交（fed5012），并已 cherry-pick 到 main 推送（577b93c），Pages 随之更新。
- [ ] T2 隐私营养标签逐项清单（写进 docs/08） — owner: agent · verify: 用户确认
  - 2026-11-12 草稿：docs/08 §9.1；等 me 确认。
- [ ] T3 在 App Store Connect 更新隐私标签与年龄分级 — owner: me · after: T2 · verify: 后台已保存
- [ ] T4 审核备注与审核员测试说明（审核员发布的内容直接通过或说明为何审核中） — owner: agent · verify: 用户确认
  - 2026-11-12 草稿：docs/08 §9.3（审核员测试步骤，说明首发会显示 In review）；等 me 确认。
- [ ] T5 支持页：申诉、删除数据 — owner: agent · verify: 页面构建
  - 2026-11-12 草稿：`docs/support.md` 新增撤回、审核中 / 复审中、申诉、举报紧急内容、删除线上数据。
- [ ] T6 提交审核 — owner: me · after: T1–T5 · verify: 审核通过
