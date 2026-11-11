# Tasks: add-moderation-console

## Now
agent 部分（T1–T3）完成，后台已部署但在配置完成前对所有人返回 503。等 me：T4 执行迁移、T5 开启 Access 并交回 team domain 与 AUD、T6 设置 secret；然后 agent 重新部署（T7）。

## M1 · 代码
- [x] T1 迁移：操作记录表与 admin_* 函数 — owner: agent · verify: SQL 测试通过（含 anon/authenticated 不能调用） · done 2026-11-12
  - evidence: `server/supabase/tests/80_moderation_console.sql` 39 条通过（全部 194 条通过）：anon/authenticated 不能调用、队列排序与发布者历史、通过 / 拒绝 / 删除 / 封禁 / 解封、全部写入记录
- [x] T2 Worker `server/admin/`：Access JWT 校验、队列 / 举报 / 记录页面、通过 / 拒绝 / 删除 / 封禁 — owner: agent · verify: vitest（JWT 各种失败、转义、同源检查、路由）+ tsc + dry-run · done 2026-11-12
  - evidence: `server/admin/`：tsc 通过；vitest 15/15（Access 令牌：有效、cookie、未配置 503、缺失、过期、错误 issuer、错误 aud、伪造签名、未知 kid、非运营者邮箱；转义；同源检查；通过时 actor 为运营者邮箱；先标记删除再删图；只读 posts/ 图片）
- [x] T3 部署 Worker（缺 Access 配置时一律 503） — owner: agent · after: T2 · verify: 未登录访问返回 503/401 · done 2026-11-12
  - evidence: `https://geoghost-admin.passerbo.workers.dev`；未配置时 `/` 与 `/img/...` 都返回 503

## M2 · 上线
- [ ] T4 在 SQL Editor 执行迁移 `server/supabase/migrations/20261112010000_moderation_console.sql` — owner: me · verify: `select public.admin_stats();` 有结果
- [ ] T5 开启 Cloudflare Access — owner: me · after: T3 · verify: 打开后台地址出现 Cloudflare 登录页
  - Workers & Pages → geoghost-admin → Settings → Domains & Routes → workers.dev 一行的「Enable Cloudflare Access」。
  - 打开生成的 Access 应用：Policies 只允许你的邮箱；在应用概览里复制 **Application Audience (AUD) Tag**；Zero Trust → Settings 里复制 **team domain**。两者都不是密钥，可以贴给 agent。
- [ ] T6 设置 secret：`cd server/admin && npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY` — owner: me · after: T3 · verify: `wrangler secret list` 有这一项
- [ ] T7 用 team domain、AUD、邮箱重新部署 — owner: agent · after: T5, T6 · verify: me 登录后看到队列
- [ ] T8 在后台审核模拟器上的测试帖子，并检查操作记录 — owner: me · after: T4, T7 · verify: 帖子在 App 里变为「已公开」
