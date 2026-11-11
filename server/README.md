# GeoGhost 服务端（线上阶段 1）

契约见 [`docs/spec/changes/setup-online-backend/design.md`](../docs/spec/changes/setup-online-backend/design.md)。本目录按契约实现 Supabase 数据库（表、RLS、RPC）和 Cloudflare Worker（图片上传 / 撤回 / 删号 / 图片读取）。

> 仓库是公开的：这里只有占位符。真实的 Supabase URL、key、Cloudflare 账号 ID 一律不要提交。

## 目录

```
server/
├── supabase/
│   ├── migrations/20261112000000_online_phase1.sql   唯一的迁移：表、索引、RLS、触发器、RPC、quota_config 初始值
│   └── tests/
│       ├── run.sh                    在一次性 postgres:16 容器里跑迁移 + 全部测试
│       ├── 00_supabase_stub.sql      仅本地测试用：模拟 Supabase 的 auth schema / 角色 / 默认权限
│       ├── 01_fixtures.sql           测试用户与辅助函数
│       └── 10_…70_*.sql              各项测试（每个文件一个事务，最后回滚）
└── worker/                           Cloudflare Worker（TypeScript），名字 geoghost-api
    ├── wrangler.toml                 R2 绑定 POSTS → geoghost-posts；vars 只有占位符
    ├── src/index.ts                  路由与处理（§7）
    ├── src/supabase.ts               Auth / PostgREST / Admin API 调用（service role）
    ├── src/upload.ts                 multipart 解析、大小限制、HEIC（ftyp）校验
    └── test/                         vitest
```

几点实现上的约定（详见迁移文件开头的注释）：

- `public.profiles` 是视图，底表是 `private.profiles`（PostgREST 不暴露 `private`）。所有人能读 `id / nickname / avatar_post_id`，其余列只有本人能读到值，别人读到 `null`。Supabase 的 Security Advisor 会把它标成 “Security Definer View”，这是有意为之。
- 日 / 月额度窗口都按 **UTC** 计算；`my_quota.resets_at` 是下一个 UTC 月初。
- 封禁 / 审核在 SQL 编辑器里做：
  ```sql
  update private.profiles set banned_at = now() where id = '<user id>';      -- 封禁
  select public.moderate_post('<post id>', 'approve');                        -- 或 'reject'
  ```
- `removed` 的帖子保留 30 天后清理，目前没有定时任务，需要时手动执行：
  ```sql
  delete from public.posts where status = 'removed' and removed_at < now() - interval '30 days';
  ```

## 应用迁移

**方式 A：SQL 编辑器。** Supabase 控制台 → SQL Editor → 粘贴 `supabase/migrations/20261112000000_online_phase1.sql` 全文 → Run。只在新项目上跑一次。

**方式 B：Supabase CLI。**

```sh
cd server
supabase init            # 仅第一次：生成 supabase/config.toml
supabase link --project-ref <project-ref>
supabase db push
```

控制台里还需要手动设置：

- Authentication → Sign In / Providers → 打开 **Allow anonymous sign-ins**（§3）。
- 建议在 Authentication → Rate Limits 里确认匿名登录的频率限制。

## 本地跑 SQL 测试

只需要 Docker（不需要本地 psql / Supabase CLI）：

```sh
server/supabase/tests/run.sh
```

脚本会启动一个临时 `postgres:16` 容器，依次执行 stub → 迁移 → fixtures → 各测试文件，打印每条断言（`ok - …`）和总数，结束时删除容器。任一断言失败则退出码非 0。换镜像：`PG_IMAGE=postgres:15 server/supabase/tests/run.sh`。

`00_supabase_stub.sql` 只用于本地测试，**不要**在 Supabase 项目上执行。

## Worker

本地检查：

```sh
cd server/worker
npm install
npx tsc --noEmit          # 类型检查
npx vitest run            # 单元测试（路由、multipart、HEIC、错误码），Supabase 与 R2 都是假的
npx wrangler deploy --dry-run --outdir dist
```

部署（需要先 `npx wrangler login`）：

```sh
cd server/worker
npx wrangler r2 bucket create geoghost-posts
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY      # 粘贴 service role / secret key，不要写进任何文件
npx wrangler deploy \
  --var SUPABASE_URL:https://<project-ref>.supabase.co \
  --var SUPABASE_ANON_KEY:<anon 或 publishable key>
```

`wrangler.toml` 里的 `SUPABASE_URL` / `SUPABASE_ANON_KEY` 是占位符；Worker 发现占位符会对所有需要 Supabase 的请求返回 500。也可以在本地把它们改成真实值再部署，但不要提交。

部署后得到 `https://geoghost-api.<子域>.workers.dev`，填到 App 的 `GGOnlineAPIURL`，`GGImageBaseURL` 为同一地址加 `/v1/images`（§2）。

Worker 返回的错误统一为 `{"error": "<code>", "message": "…"}`，`error` 取值：`unauthorized`(401) · `forbidden` / `banned`(403) · `not_found`(404) · `invalid_status`(409) · `too_large`(413) · `unsupported_media_type`(415) · `bad_request`(400) · `method_not_allowed`(405) · `internal`(500) · `upstream`(502)。

## 端到端冒烟测试

部署完成后，对真实后端跑一遍完整流程（临时游客 → 发布 → 可见性 → 额度 → 撤回 → 删除游客，结束时不留数据）：

```sh
server/scripts/smoke.sh   # 读取 Config/Online.xcconfig
```

## 审核后台（`server/admin/`，Worker `geoghost-admin`）

独立的 Worker，前面由 Cloudflare Access 保护，只放行 `ALLOWED_EMAILS` 里的运营者。Access、Supabase 任一项没配好时一律返回 503。设计见 `docs/spec/changes/add-moderation-console/design.md`。

1. 在 SQL Editor 执行 `supabase/migrations/20261112010000_moderation_console.sql`（只执行一次）。
2. Workers & Pages → geoghost-admin → Settings → Domains & Routes → workers.dev → **Enable Cloudflare Access**；在生成的 Access 应用里把策略限制为自己的邮箱，复制 **Application Audience (AUD) Tag** 和 Zero Trust 的 **team domain**。
3. `cd server/admin && npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY`
4. 部署（真实值只在命令里传，不写进 `wrangler.toml`）：
   ```sh
   npm run vendor
   npx wrangler deploy --var SUPABASE_URL:https://<ref>.supabase.co \
     --var ACCESS_TEAM_DOMAIN:<team>.cloudflareaccess.com --var ACCESS_AUD:<aud tag> \
     --var ALLOWED_EMAILS:<you@example.com>
   ```

图片是 HEIC，页面在浏览器里用 libheif（WebAssembly）解码成 PNG，所以任何现代浏览器都能看。解码库来自 npm 的 `libheif-js`（LGPL-3.0），部署前 `npm run vendor` 会把它复制到 `public/vendor/`（不入库）。

本地检查：`npm install && npx tsc --noEmit && npx vitest run`。
