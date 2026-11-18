# Tasks: add-update-gate-and-switches

## Now
提案、设计已写好。T1–T10 都未开始。
- 2026-11-19：实现会话启动时周用量已 88%（停止线 85%），没有写任何规格或代码就停下了。周额度重置后从 T1 开始。
- 提交分支（2026-11-19 定）：直接提交在 `fix/services-environment-crash`，不移动或快进任何分支；分支怎么合并由 me 决定。

## M1 · 规格
- [ ] T1 delta `online-availability`（版本过低、轻提示、暂停发布、暂停新用户、公告、删除数据不受限） — owner: agent · verify: check-delta 无错误

## M2 · 服务端
- [ ] T2 迁移：`app_config`、版本比较函数、各写入 RPC 的检查、`admin_set_app_config` 与记录 — owner: agent · verify: SQL 测试（过低 / 缺头 / 暂停发布 / 暂停新用户 / 已有用户改昵称不受影响 / 删除数据不受影响）
- [ ] T3 Worker 版本检查（上传、撤回；删除我的数据除外） — owner: agent · verify: vitest
- [ ] T4 审核后台「设置」页 — owner: agent · verify: vitest（权限、转义、同源、记录）

## M3 · 客户端
- [ ] T5 所有请求带版本头；新的 `OnlineRefusal` 与文案 — owner: agent · verify: 单元测试
- [ ] T6 `AppConfigService`（缓存、失败沿用、从未成功放行）与版本比较 — owner: agent · verify: 单元测试
- [ ] T7 界面：需要更新、新版本轻提示、暂停说明、公告；中 / 日翻译 — owner: agent · verify: 模拟器截图

## M4 · 上线
- [ ] T8 在 SQL Editor 执行迁移；设置 `min_online_version = 1.1.0`、`latest_version = 1.1.0` — owner: me · after: T2 · verify: `select * from app_config;`
- [ ] T9 部署两个 Worker — owner: agent · after: T3, T4, T8 · verify: 冒烟测试通过；后台能改设置
- [ ] T10 演练：把 `min_online_version` 调到 9.9.9，确认模拟器停用线上功能且本地功能正常，再改回 — owner: me + agent · after: T7, T9 · verify: 截图
