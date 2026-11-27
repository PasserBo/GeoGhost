# Board

> 阶段 1 线上 MVP。按顺序做；同一行内 agent 与 me 的任务可以并行。最后更新：2026-11-27

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
| 10 | [improve-cutout-defaults](changes/improve-cutout-defaults/proposal.md) | in-progress | T1–T6 完成；剩 T7 真机基准照片（建议是否正确、点一下 / 自动画圈是否成功），并重录 UI 快照 | me |
| 11 | [add-cutout-coaching](changes/add-cutout-coaching/proposal.md) | in-progress | T1–T6 完成（示例照片已打包进 App，空图鉴可练习）；剩 T7 真机确认三张能抠出 | me |
| 12 | [improve-first-run](changes/improve-first-run/proposal.md) | in-progress | T1–T7 完成；剩 T8 真机走查，并重录 UI 快照基准图 | me |
| 13 | [add-library-scan-import](changes/add-library-scan-import/proposal.md) | idea | 暂不做，只保留提案（工作量大）；重启时先回答开放问题 | me |

### 宣传与分享（2026-11-23 讨论）

> 宣传先走 Reddit：像自发分享的用户那样发在日本拍到的贴纸（原图配分享卡），不发下载链接。区域合集卡暂缓，以后单独讨论。

| # | 变更 | 状态 | 下一步 | 负责 |
|---|---|---|---|---|
| 14 | [add-series-share-card](changes/add-series-share-card/proposal.md) | in-progress | 1.2.0 (115) 已在 TestFlight，含随贴纸形状调整的版面；剩 T11 真机走查、T12 读许可协议的地图附件，然后归档 | me |
| 15 | [improve-world-map](changes/improve-world-map/proposal.md) | in-progress | 1.2.0 (119) 在 TestFlight；me 真机反馈流畅，但一处作品多时没法靠滑动挑选 → 加了网格面板和自己位置的圆点，已合并 main；1.2.0 (125) 于 2026-11-27 提交 App Store 审核，等待审核中；剩 T11、T14 真机走查；统计事件等 me 决定 | me |
