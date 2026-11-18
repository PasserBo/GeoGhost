# Board

> 阶段 1 线上 MVP。按顺序做；同一行内 agent 与 me 的任务可以并行。最后更新：2026-11-19

| # | 变更 | 状态 | 下一步 | 负责 |
|---|---|---|---|---|
| 1 | [setup-online-backend](changes/setup-online-backend/proposal.md) | in-progress | 已完成，合并 main 后归档 | agent |
| 2 | [add-guest-identity](changes/add-guest-identity/proposal.md) | in-progress | T7 确认社区规则正文；T11 真机检查 | me |
| 3 | [add-publishing](changes/add-publishing/proposal.md) | in-progress | T11 真机发布并审核（端到端已在模拟器验证） | me |
| 4 | [add-explore-map](changes/add-explore-map/proposal.md) | in-progress | 界面完成并验证；剩 T7 种子内容、T8 真机 | me |
| 5 | [add-likes-and-saves](changes/add-likes-and-saves/proposal.md) | accepted | 等 4 | agent |
| 6 | [add-reporting-and-blocking](changes/add-reporting-and-blocking/proposal.md) | in-progress | 迁移已执行；需要一张别人的公开贴纸来走查举报 / 屏蔽 / 复审，然后 T4 审核手册；通知待讨论（不先做） | me |
| 7 | [add-moderation-console](changes/add-moderation-console/proposal.md) | in-progress | 已完成并验证，待归档 | agent |
| 7b | [add-update-gate-and-switches](changes/add-update-gate-and-switches/proposal.md) | in-progress | T1–T10 完成；新版本上传 TestFlight（旧 1.1.0 构建的线上写入会被拒），合并 main 后归档 | me |
| 8 | [prepare-ugc-release](changes/prepare-ugc-release/proposal.md) | in-progress | 文案已起草，等 me 确认并合并 main（页面才上线） | me |
| 9 | [add-apple-account-linking](changes/add-apple-account-linking/proposal.md) | accepted | 阶段 1 上线后开始 | agent |

阶段 1 上线 = 1–8（含 7b）完成。9 是阶段 1.5，在阶段 2（关注、徽章）之前完成。

### 阶段 1 之后：新用户上手（2026-11-19 调研；10–12 已 accepted，13 暂不做）

> 依据 [research/onboarding-and-cutout.md](../research/onboarding-and-cutout.md)。建议顺序 10 → 11；12 可与 10 并行。13 暂不做（2026-11-19），只保留提案。

| # | 变更 | 状态 | 下一步 | 负责 |
|---|---|---|---|---|
| 10 | [improve-cutout-defaults](changes/improve-cutout-defaults/proposal.md) | in-progress | T1–T4 完成（建议选区、点一下就选中、失败两次后框选 / 整张照片）；剩 T5 失败时自动套索、T6 文档；me 真机基准 T7 | agent |
| 11 | [add-cutout-coaching](changes/add-cutout-coaching/proposal.md) | accepted | 等 10；me 提供 2–3 张示例贴纸照片 | me |
| 12 | [improve-first-run](changes/improve-first-run/proposal.md) | in-progress | T1–T7 完成；剩 T8 真机走查，并重录 UI 快照基准图 | me |
| 13 | [add-library-scan-import](changes/add-library-scan-import/proposal.md) | idea | 暂不做，只保留提案（工作量大）；重启时先回答开放问题 | me |
