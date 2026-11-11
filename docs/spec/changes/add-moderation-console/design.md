# Design: add-moderation-console

## 组成

- **Worker `geoghost-admin`**（`server/admin/`），独立于 `geoghost-api`。workers.dev 上开启 Cloudflare Access（只放行运营者邮箱）。
- Worker 校验每个请求的 `Cf-Access-Jwt-Assertion`：RS256，公钥来自 `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`，`aud` 等于 Access 应用的 AUD，`iss` 等于 team 域名，未过期；邮箱在 `ALLOWED_EMAILS` 里（双保险）。缺配置时一律 503，不放行。
- 页面由 Worker 输出 HTML（无框架、无外部资源），所有用户内容转义。操作是同源表单 POST（检查 `Origin`），处理后 303 跳回（刷新不会重复提交）。
- 图片：`GET /img/<key>` 从 R2 读（同一个 bucket 绑定），只允许 `posts/` 前缀。
- 数据：service role 调用下面的 RPC。删除时 Worker 先调 `admin_remove_post`（帖子立即消失并拿到图片 key），再删 R2 两张图；删图失败只会留下没人能看到的孤立文件。

## 数据库（迁移 `20261112010000_moderation_console.sql`，全部只给 service_role）

| 函数 | 作用 |
|---|---|
| `admin_stats()` | 待审核数、最早待审核时间、有未处理举报的帖子数、最早未处理举报时间 |
| `admin_queue(kind, max_rows)` | `pending`：待审核，最早在前；`reported`：有未处理举报的帖子，最早举报在前。带发布者昵称、通过次数、未通过（hidden）次数、是否封禁、未处理举报数与原因 |
| `admin_post_reports(post_id)` | 该帖全部举报（原因、说明、时间、处理结果） |
| `admin_moderate(post_id, decision, actor)` | 调 `moderate_post` 并记录 |
| `admin_remove_post(post_id, actor)` | 状态改 `removed`，关闭举报（`removed`），记录 |
| `admin_set_ban(user_id, banned, actor, note)` | 设置 / 清除 `banned_at`，记录 |
| `admin_log(max_rows)` | 最近的操作记录 |

`private.moderation_log`：`at, actor, action(approve/reject/remove/ban/unban), post_id, user_id, note`。不设外键，帖子或用户删除后记录仍在。

## 配置

| 名称 | 类型 | 说明 |
|---|---|---|
| `POSTS` | R2 绑定 | `geoghost-posts` |
| `SUPABASE_URL` | var | 同 api |
| `SUPABASE_SERVICE_ROLE_KEY` | secret | 同 api |
| `ACCESS_TEAM_DOMAIN` | var | 如 `passerbo.cloudflareaccess.com` |
| `ACCESS_AUD` | var | Access 应用的 Application Audience (AUD) Tag |
| `ALLOWED_EMAILS` | var | 逗号分隔 |
