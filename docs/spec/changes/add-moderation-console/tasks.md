# Tasks: add-moderation-console

## Now
全部完成，可以归档。归档前把 design.md 中长期有效的部分并入 `capabilities/moderation-console/design.md`。

## M1 · 代码
- [x] T1 迁移：操作记录表与 admin_* 函数 — owner: agent · verify: SQL 测试通过（含 anon/authenticated 不能调用） · done 2026-11-12
  - evidence: `server/supabase/tests/80_moderation_console.sql` 39 条通过（全部 194 条通过）：anon/authenticated 不能调用、队列排序与发布者历史、通过 / 拒绝 / 删除 / 封禁 / 解封、全部写入记录
- [x] T2 Worker `server/admin/`：Access JWT 校验、队列 / 举报 / 记录页面、通过 / 拒绝 / 删除 / 封禁 — owner: agent · verify: vitest（JWT 各种失败、转义、同源检查、路由）+ tsc + dry-run · done 2026-11-12
  - evidence: `server/admin/`：tsc 通过；vitest 15/15（Access 令牌：有效、cookie、未配置 503、缺失、过期、错误 issuer、错误 aud、伪造签名、未知 kid、非运营者邮箱；转义；同源检查；通过时 actor 为运营者邮箱；先标记删除再删图；只读 posts/ 图片）
- [x] T3 部署 Worker（缺 Access 配置时一律 503） — owner: agent · after: T2 · verify: 未登录访问返回 503/401 · done 2026-11-12
  - evidence: `https://geoghost-admin.passerbo.workers.dev`；未配置时 `/` 与 `/img/...` 都返回 503

## M2 · 上线
- [x] T4 在 SQL Editor 执行迁移 `server/supabase/migrations/20261112010000_moderation_console.sql` — owner: me · verify: `select public.admin_stats();` 有结果 · done 2026-11-12
  - evidence: 用 anon key 调 `admin_stats` 返回 42501 permission denied（函数存在且对客户端关闭）
- [x] T5 开启 Cloudflare Access — owner: me · after: T3 · verify: 打开后台地址出现 Cloudflare 登录页 · done 2026-11-12
  - evidence: Access 已开启（team `passerbo-studio.cloudflareaccess.com`），策略为「Cloudflare account members」（workers.dev 一键开启时没有按邮箱的选项）；未登录访问被 302 到 Access 登录页
  - Workers & Pages → geoghost-admin → Settings → Domains & Routes → workers.dev 一行的「Enable Cloudflare Access」。
  - 打开生成的 Access 应用：Policies 只允许你的邮箱；在应用概览里复制 **Application Audience (AUD) Tag**；Zero Trust → Settings 里复制 **team domain**。两者都不是密钥，可以贴给 agent。
- [x] T6 设置 secret：`cd server/admin && npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY` — owner: me · after: T3 · verify: `wrangler secret list` 有这一项 · done 2026-11-12
  - evidence: 用户在终端 `wrangler secret put` 成功（geoghost-admin）
- [x] T7 用 team domain、AUD、邮箱重新部署 — owner: agent · after: T5, T6 · verify: me 登录后看到队列 · done 2026-11-12
  - evidence: me 登录 Safari / Chrome 后看到队列与图片（浏览器内 libheif 解码）
  - 2026-11-12 已用 team domain、AUD、`ALLOWED_EMAILS=passerbo.studio@gmail.com`（Cloudflare 账号邮箱）部署；伪造令牌也被边缘 302。等 T4、T6 后由 me 登录确认。
- [x] T8 在后台审核模拟器上的测试帖子，并检查操作记录 — owner: me · after: T4, T7 · verify: 帖子在 App 里变为「已公开」 · done 2026-11-12
  - evidence: me 在后台点通过；App 同步为已公开，匿名世界地图可见
