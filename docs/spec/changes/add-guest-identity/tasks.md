# Tasks: add-guest-identity

## Now
会话层 T1–T4 完成（客户端代码在 `GeoGhost/Services/Online/`）。下一步：T6 昵称与社区规则页、T8 设置页线上身份区；T5 等后端部署。

## M1 · 会话层
- [x] T1 Keychain 存取（会话存储，本机、首次解锁后可读、不同步） — owner: agent · verify: 单元测试 · done 2026-11-12
  - evidence: `KeychainStoreTests.testSetUpdateReadRemove`
- [x] T2 认证客户端：匿名登录、刷新 — owner: agent · verify: 单元测试（URLProtocol 替身） · done 2026-11-12
  - evidence: `SupabaseAuthClientTests`（4 个）
- [x] T3 `OnlineSession`：按需创建、单飞刷新、持久化、失效处理 — owner: agent · after: T1, T2 · verify: 单元测试（并发刷新只发一次请求；刷新失败清会话且不自动新建） · done 2026-11-12
  - evidence: `OnlineSessionTests`（6 个：按需创建、并发只建一个游客、刷新单飞、失效不自动新建且重启后仍提示、确认后新建、退出）
- [x] T4 PostgREST 客户端：查询、RPC、错误 hint 映射为本地错误 — owner: agent · verify: 单元测试 · done 2026-11-12
  - evidence: `PostgrestClientTests`（4 个：snake_case 参数、无身份用 anon key、9 种 hint 映射、401 刷新后重试一次）
- [ ] T5 冒烟：真实后端上匿名登录与刷新 — owner: agent · after: T3, setup-online-backend T11 · verify: 测试输出

## M2 · 界面
- [ ] T6 昵称与社区规则页（发布前出现；规则版本更新后再次出现） — owner: agent · after: T4 · verify: 模拟器截图
- [ ] T7 社区规则正文（EULA，零容忍条款）放在 docs/ 公开页 — owner: agent 起草 · me 确认 · verify: 用户确认
- [ ] T8 设置页「线上身份」区：昵称、改昵称（冷却提示）、删除我的线上数据 — owner: agent · after: T4 · verify: 模拟器截图
- [ ] T9 身份失效提示 — owner: agent · after: T3 · verify: 单元测试 + 模拟器

## M3 · 验证
- [ ] T10 研究并验证游客换机方案（09 §7） — owner: agent · verify: 写进 proposal Decisions
- [ ] T11 真机：重装后仍是同一游客；删除线上数据 — owner: me · after: T8 · verify: 真机操作通过
