# Tasks: add-update-gate-and-switches

## Now
2026-11-19：T1–T6 完成并提交（`fix/services-environment-crash`）；T7 只差 App Store app id（已问 me）。T8 迁移已就绪：`server/supabase/migrations/20261119000000_app_config.sql`，等 me 在 SQL Editor 执行；执行后 agent 做 T9（部署两个 Worker + `smoke.sh`）。
- 实现时的选择，需要 me 确认：点赞、收藏、屏蔽也按版本拒绝（设计写的是「视情况」）；公告每种语言最多 280 字；版本过低时设置里的改昵称、已屏蔽用户、全部撤回不可用，删除线上数据始终可用。
- 已知小问题（改动之前就有）：主按钮停用时样式不变灰（`PrimaryButtonStyle` 不看 isEnabled），暂停发布时「公開」按钮看起来仍可点（实际点了没反应）。

## M1 · 规格
- [x] T1 delta `online-availability`（版本过低、轻提示、暂停发布、暂停新用户、公告、删除数据不受限） — owner: agent · verify: check-delta 无错误 · 证据：check-delta 无输出（无错误）

## M2 · 服务端
- [x] T2 迁移：`app_config`、版本比较函数、各写入 RPC 的检查、`admin_set_app_config` 与记录 — owner: agent · verify: SQL 测试（过低 / 缺头 / 暂停发布 / 暂停新用户 / 已有用户改昵称不受影响 / 删除数据不受影响） · 证据：`server/supabase/tests/run.sh` 全部 259 条通过，新增 `90_app_config.sql` 36 条（含配额也会拒绝时仍报 publishing_paused、过低优先于暂停）
- [x] T3 Worker 版本检查（上传、撤回；删除我的数据除外） — owner: agent · verify: vitest · 证据：`server/worker` `npx vitest run` 39 条通过（新增 version gate 6 条：过低 / 缺头 426、新版本可上传、撤回 426、删除我的数据不查版本）；`smoke.sh` 改为带版本头并检查 426
- [x] T4 审核后台「设置」页 — owner: agent · verify: vitest（权限、转义、同源、记录） · 证据：`server/admin` `npx vitest run` 22 条通过（新增：设置页显示与转义、保存时 actor 与暂停 / 空公告、跨站拒绝、非法设置显示 400、记录里显示「运营设置」）；`tsc --noEmit` 无错误

## M3 · 客户端
- [x] T5 所有请求带版本头；新的 `OnlineRefusal` 与文案 — owner: agent · verify: 单元测试 · 证据：`VersionHeaderTests`（每个请求带 `X-GeoGhost-Version`；三个新提示与 Worker 426 映射为各自的拒绝；文案不含额度字样）；全部单元测试 112 条通过（CDB94C9B）
- [x] T6 `AppConfigService`（缓存、失败沿用、从未成功放行）与版本比较 — owner: agent · verify: 单元测试 · 证据：`AppVersionTests`、`AppConfigServiceTests`（从未读到放行、版本→可用性、暂停、10 分钟缓存、失败沿用上次且跨启动保留、公告按语言回退英文、解析服务器行）
- [ ] T7 界面：需要更新、新版本轻提示、暂停说明、公告；中 / 日翻译 — owner: agent · verify: 模拟器截图 · 进度：界面与中 / 日翻译完成，模拟器 4F71E5A0 截图（世界地图 / 发布 / 设置 需要更新；日文设置有新版本；日文发布预览公告 + 暂停）存在会话笔记 `update-gate-shots/`；**未勾**：App Store 链接里的 app id 还是占位 `0000000000`（`AvailabilityViews.swift` › `AppStoreLink.appID`），等 me 提供

## M4 · 上线
- [ ] T8 在 SQL Editor 执行迁移；设置 `min_online_version = 1.1.0`、`latest_version = 1.1.0` — owner: me · after: T2 · verify: `select * from app_config;`
- [ ] T9 部署两个 Worker — owner: agent · after: T3, T4, T8 · verify: 冒烟测试通过；后台能改设置
- [ ] T10 演练：把 `min_online_version` 调到 9.9.9，确认模拟器停用线上功能且本地功能正常，再改回 — owner: me + agent · after: T7, T9 · verify: 截图
