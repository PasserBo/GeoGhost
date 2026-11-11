# Tasks: setup-online-backend

## Now
全部完成。合并到 main 后归档。

## M0 · 云端资源
- [x] T1 建 Supabase 项目 — owner: me · verify: 能打开项目 Dashboard · done 2026-11-13
  - evidence: 项目 ref `kqanscutffrltxvsahbg`；URL 与 publishable key 已填入 `Config/Online.xcconfig`
  - Region 选 Northeast Asia (Tokyo)，Free plan，项目名 `geoghost`；数据库密码存进密码管理器。
  - 交回给 agent：Project URL 与 anon（publishable）key（Settings → API）。两者是公开信息，可以直接贴在对话里。**service_role key 不要贴**，T5 里直接存进 Worker secret。
- [x] T2 开启匿名登录 — owner: me · after: T1 · verify: Authentication → Sign In / Providers 里 Anonymous sign-ins 为开启 · done 2026-11-13
  - evidence: `GET /auth/v1/settings` 返回 `anonymous_users: true`
  - 其余登录方式先不开。
- [x] T3 建 R2 bucket — owner: me · verify: Cloudflare Dashboard → R2 里能看到 `geoghost-posts` · done 2026-11-12
  - evidence: 用户确认已建好
  - 首次启用 R2 可能要求绑定付款方式（免费额度内不扣费）。bucket 保持私有，不开 r2.dev 公开访问。
- [x] T4 执行数据库迁移 — owner: me · after: T1, T7 · verify: SQL Editor 执行 `select key, value from quota_config;` 返回 9 行 · done 2026-11-12
  - evidence: 用户在 SQL Editor 查询 quota_config 返回 9 行，值与 design §6 一致
  - 把 `server/supabase/migrations/` 里的 SQL 整段粘到 SQL Editor 执行（步骤见 `server/README.md`）。
- [x] T5 部署 Worker — owner: me · after: T3, T8 · verify: `curl <Worker URL>/v1/images/none` 返回 404 JSON · done 2026-11-12
  - evidence: Worker 地址 `https://geoghost-api.passerbo.workers.dev`；用户在终端设置 secret 成功（`wrangler secret list` 有 SUPABASE_SERVICE_ROLE_KEY）
  - 2026-11-12 agent 已部署（`https://geoghost-api.passerbo.workers.dev`，版本 01a6ad42），`/v1/images/none` → 404、`DELETE /v1/me` 无 token → 401。**还差 me：`npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY`**，之后才算完成。
  - `server/worker` 下：`npm install` → `npx wrangler login` → `npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY` → `npx wrangler deploy --var SUPABASE_URL:https://<ref>.supabase.co --var SUPABASE_ANON_KEY:<anon key>`。
  - 仓库是公开的：真实值只在部署命令里传，**不要写进 `wrangler.toml`**（里面只有占位符；占位符没换掉时 Worker 返回 500）。
  - 交回给 agent：Worker URL。
- [x] T6 决定是否买自有域名 — owner: me · verify: 在 proposal 的 Decisions 里记下结论 · done 2026-11-12
  - evidence: 用户决定暂不购买（2026-11-12）

## M1 · 代码
- [x] T7 SQL 迁移与本地测试（表、RLS、RPC、额度） — owner: agent · verify: Docker Postgres 上全部 SQL 测试通过 · done 2026-11-12
  - evidence: `server/supabase/tests/run.sh` → 155 assertions passed, 0 failed（postgres:16 + 本地 Supabase 替身）；实现时的澄清记在 design.md §10
- [x] T8 上传 Worker — owner: agent · verify: `tsc --noEmit` 与 `wrangler deploy --dry-run` 通过 · done 2026-11-12
  - evidence: tsc 通过；vitest 33/33；dry-run 打包 14.9 KiB；仓库内无真实密钥
- [x] T9 App 读取线上配置（`Config/Online.xcconfig` → Info.plist → `OnlineConfig`），未配置时隐藏线上功能 — owner: agent · verify: 单元测试 + 构建通过 · done 2026-11-12
  - evidence: `OnlineConfigTests`（3 个）；空配置构建时 `AppServices.online == nil`
- [x] T10 端到端冒烟脚本 `server/scripts/smoke.sh` — owner: agent · after: T7, T8 · verify: 写完后 T11 使用 · done 2026-11-12
  - evidence: `server/scripts/smoke.sh`：建临时游客 → 发布 → 可见性 → 额度 → 撤回 → 删除游客，结束时无残留
- [x] T11 跑冒烟测试 — owner: agent · after: T4, T5, T10 · verify: 脚本输出全部 OK · done 2026-11-12
  - evidence: 真实后端 28/28 通过（匿名登录、未建资料被拒、坐标吸附、PNG 被拒 415、上传后 pending、他人与世界地图看不到、额度计数、撤回删图且不返还额度、删除线上数据）
