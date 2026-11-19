# Design: setup-online-backend

> 阶段 1 所有线上功能共用的后端契约。客户端（Swift）与服务端（SQL、Worker）都按本文实现；改契约先改这里。
> 决策背景：[ADR-007](../../../01-technical-architecture.md)、[线上身份与游客功能设计](../../../09-online-identity.md)。

## 1. 组成

```
App ──(Supabase Auth: 匿名登录 / 刷新)──────────────▶ Supabase Auth
App ──(PostgREST: 查询 + RPC，带用户 JWT)───────────▶ Supabase Postgres（RLS）
App ──(HTTPS，带用户 JWT)──▶ Worker ──(R2 绑定)────▶ R2 bucket geoghost-posts
                              └──(service role)────▶ Supabase（校验归属、改状态）
App ──(GET 图片)───────────▶ 图片地址（MVP：Worker；有自有域名后：R2 自定义域名 + CDN）
```

- 客户端不依赖任何第三方 SDK：Auth、PostgREST、Worker 都是普通 HTTPS + JSON。
- **图片只经过 Worker 上传**，客户端拿不到 R2 凭证；Worker 校验身份、归属、大小和格式后再写入 R2。
- service role key 只存在 Worker 的 secret 里，永不进仓库、永不进 App。
- Supabase 的 URL 和 anon key 是公开信息（权限由 RLS 决定），写在 `Config/Online.xcconfig`，可以提交。

## 2. 配置

| 键（Info.plist） | 含义 | 例 |
|---|---|---|
| `GGSupabaseURL` | Supabase 项目 URL | `https://xxxx.supabase.co` |
| `GGSupabaseAnonKey` | anon / publishable key | `eyJ…` 或 `sb_publishable_…` |
| `GGOnlineAPIURL` | Worker 根地址 | `https://geoghost-api.passerbo.workers.dev` |
| `GGImageBaseURL` | 图片根地址，客户端拼 `<base>/<key>` | MVP 与 `GGOnlineAPIURL` + `/v1/images` 相同 |

四个键任一为空时，线上功能整体隐藏（App 表现与 v1.0 相同）。

## 3. 身份

- 匿名登录：`POST {supabase}/auth/v1/signup`，header `apikey: <anon>`，body `{}`。Supabase 后台需开启 *Allow anonymous sign-ins*。返回 `access_token`、`refresh_token`、`expires_in`、`user.id`、`user.is_anonymous`。
- 刷新：`POST {supabase}/auth/v1/token?grant_type=refresh_token`，body `{"refresh_token": "…"}`。refresh token 一次性；同一 token 并发刷新会导致会话失效，客户端必须**单飞**（同一时刻只有一个刷新请求）。
- 会话（access + refresh + 过期时间 + user id）存 Keychain，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不同步 iCloud（换机方案待验证，见 09 §7）。
- 会话在第一次需要身份时才创建（点赞、收藏、举报、屏蔽、发布）；浏览不创建。
- access token 剩余有效期 < 60 秒时先刷新再请求。刷新返回 400/401（refresh token 失效）时：清除本地会话；**不自动创建新游客**，让上层提示「线上身份已失效」（避免静默丢失归属）。

## 4. 数据（Postgres，schema `public`）

所有时间为 `timestamptz`。`auth.uid()` 为当前用户。

| 表 | 主要列 | 说明 |
|---|---|---|
| `profiles` | `id`(= auth.users.id) · `nickname` · `avatar_post_id` · `terms_version` · `terms_accepted_at` · `nickname_changed_at` · `approved_count` · `banned_at` · `created_at` | 公开资料。昵称 1–24 字符，可重复 |
| `posts` | `id` · `author_id` · `client_artwork_id` · `status` · `kind` · `lat` · `lng` · `locality` · `country_code` · `captured_on`(date) · `width` · `height` · `image_key` · `thumb_key` · `like_count` · `created_at` · `published_at` | `unique(author_id, client_artwork_id)`（不含 `removed`）保证重试不重复；撤回后再发布是新帖子、新 ID |
| `likes` | `user_id` · `post_id` · `created_at` | 主键 (user_id, post_id) |
| `saves` | `user_id` · `post_id` · `created_at` | 灵感夹；主键同上 |
| `reports` | `id` · `reporter_id` · `post_id` · `reason` · `note` · `created_at` · `resolved_at` · `resolution` | `unique(reporter_id, post_id)` |
| `blocks` | `blocker_id` · `blocked_id` · `created_at` | 主键 (blocker_id, blocked_id) |
| `quota_config` | `key` · `value` | 额度与阈值，见 §6 |

`posts.status`：

| 值 | 含义 | 谁能看到 |
|---|---|---|
| `uploading` | 已占位，图片未传完 | 作者 |
| `pending` | 等人工审核；`published_at` 不为空时是被多人举报后的重新审核（2026-11-12，迁移 `20261112030000`） | 作者（首次显示「审核中」，复审显示「复审中」） |
| `public` | 公开 | 所有人（屏蔽关系除外） |
| `hidden` | 审核拒绝（2026-11-12 起被举报不再直接进入此状态） | 作者（显示「未通过」） |
| `removed` | 作者撤回 / 删除；图片已删 | 无人；行保留 30 天后清理 |

坐标：客户端上传前先吸附到网格，服务端在 `create_post` 里**再吸附一次**（不信任客户端）：
`lat = round(lat / 0.001) * 0.001`，`lng = round(lng / 0.001) * 0.001`（约 100 m）。时间只存日期。

## 5. RLS 与 RPC

表默认全部开启 RLS；写操作除 likes / saves / blocks 外一律走 `security definer` 函数。

**读**

- `posts`：`status = 'public'` 且作者未被封禁，且（未登录或作者不在我的屏蔽列表里）→ 所有人可读；作者可读自己的全部帖子。2026-11-12 起（add-reporting-and-blocking，迁移 `20261112020000`）：我举报过的帖子对我不可读。
- `profiles`：所有人可读 `id, nickname, avatar_post_id`；其余列只有本人可读。
- `likes` / `saves` / `blocks`：只能读自己的。`reports`：客户端不可读。

**写（RPC，`POST {supabase}/rest/v1/rpc/<name>`）**

| 函数 | 参数 | 规则 | 返回 |
|---|---|---|---|
| `upsert_profile` | `nickname`, `terms_version` | 首次调用创建资料并记录同意条款；改昵称 7 天 1 次；被封禁拒绝 | profile |
| `create_post` | `client_artwork_id`, `kind`, `lat`, `lng`, `locality`, `country_code`, `captured_on`, `width`, `height` | 需已有 profile 且同意当前条款；未封禁；检查日 / 月额度（按窗口内**创建**的帖子数计，任何状态都算，撤回不返还额度）；同一 `client_artwork_id` 再次调用返回已有帖子 | `{post_id, status, image_key, thumb_key}` |
| `explore` | `min_lat`, `min_lng`, `max_lat`, `max_lng`, `cell_deg` | 视口内公开帖子；`cell_deg > 0` 时按网格聚合，每格返回数量 + 最新一张；否则返回最多 200 张 | 列表 |
| `report_post` | `post_id`, `reason`, `note` | 每日额度；同一人同一帖只算一次；不同举报人达到阈值时回到 `pending` 重新审核（2026-11-12 前为 `hidden`） | `{ok}` |
| `my_quota` | — | 本月 / 今日已用与上限 | `{month_used, month_limit, day_used, day_limit, resets_at}` |

**直接写表（RLS）**：`likes`、`saves`、`blocks` 只能插入 / 删除 `user_id = auth.uid()` 的行；`saves` 插入时由触发器检查上限；`likes` 由触发器维护 `posts.like_count` 并检查每日上限。

**只给 Worker（service role）**：`complete_post_upload(post_id)`：`uploading` → 作者 `approved_count` ≥ 信任阈值则 `public`（写 `published_at`），否则 `pending`。`moderate_post(post_id, decision)`：审核 `approve` / `reject`，通过时作者 `approved_count + 1`。

## 6. 额度与阈值（`quota_config` 初始值）

| key | 值 | 来源 |
|---|---|---|
| `posts_per_month` | 20 | 09 §4 |
| `posts_per_day` | 5 | 09 §4 |
| `trust_threshold` | 3 | 前 3 张人工审核 |
| `saves_max` | 50 | 灵感夹上限 |
| `likes_per_day` | 300 | |
| `reports_per_day` | 20 | |
| `report_hide_threshold` | 3 | 不同举报人数 |
| `nickname_change_days` | 7 | |
| `terms_version` | 1 | 条款更新时 +1，用户需重新同意 |

拒绝时 RPC 抛出带固定 `hint` 的错误，客户端据此显示原因：`quota_day` · `quota_month` · `saves_full` · `likes_day` · `reports_day` · `banned` · `terms_required` · `profile_required` · `nickname_cooldown`。

## 7. Worker API（`GGOnlineAPIURL`）

所有写接口带 `Authorization: Bearer <access_token>`；Worker 用 `GET {supabase}/auth/v1/user` 校验 token 并取得 user id。

| 方法 | 路径 | 说明 |
|---|---|---|
| `PUT` | `/v1/posts/{post_id}/images` | `multipart/form-data`：`full`（≤ 1.5 MB）、`thumb`（≤ 300 KB），都必须是 HEIC（检查 `ftyp` 品牌 `heic`/`heix`/`mif1`）。帖子必须属于该用户且为 `uploading`。写入 R2 后调用 `complete_post_upload`，返回 `{status}`。`uploading` 时重复调用覆盖图片；已是 `pending`/`public`/`hidden` 时直接返回当前状态、不覆盖；`removed` 返回 409 |
| `DELETE` | `/v1/posts/{post_id}` | 作者撤回：删除 R2 中两张图，状态改 `removed`，返回 `{status:"removed"}`；可重复调用 |
| `DELETE` | `/v1/me` | 删除我的线上数据：删除全部图片，删除 auth 用户（级联删除资料、帖子、点赞、收藏、屏蔽；举报保留但 `reporter_id` 置空） |
| `GET` | `/v1/images/{key}` | MVP 的图片读取：从 R2 读出，`Cache-Control: public, max-age=31536000, immutable`；不存在时 404 |

R2 key：`posts/{post_id}/full.heic`、`posts/{post_id}/thumb.heic`。图片内容不变，换图时 key 不变但只发生在 `uploading` 阶段（尚未公开），所以可以永久缓存。

错误响应统一为 `{"error": "<code>", "message": "<人看的说明>"}`，HTTP 状态码：401 未登录 / token 无效，403 不是作者或被封禁，404 不存在，409 状态不对，413 太大，415 格式不对。

## 8. 上传顺序（客户端）

1. 确保有会话（§3）与 profile（首次发布时 `upsert_profile`）。
2. 本地生成两张 HEIC：长边 1024（`full`）、长边 400（`thumb`），保留透明，**不写任何元数据**。
3. `create_post`（带吸附后的坐标）→ 得到 `post_id`，本地 `Artwork` 记下 `post_id` 与状态 `uploading`。
4. `PUT /v1/posts/{post_id}/images` → 得到 `pending` 或 `public`，写回本地。
5. 第 4 步失败可原样重试；第 3 步重试因 `client_artwork_id` 唯一而不会重复占额度。

## 9. 以后再做（不在本变更）

- App Attest：Worker 在上传前校验设备断言（`add-reporting-and-blocking` 之后评估）。
- DeviceCheck 标记被封设备。
- 自有域名 + R2 自定义域名，替换 `GGImageBaseURL`。
- 审核后台：MVP 用 Supabase 控制台 + SQL（`moderate_post`）。

## 10. 实现时的澄清（2026-11-12）

服务端实现（`server/`）时补充的细节，客户端按此对接：

- **profiles 列可见性**：RLS 只能按行过滤，所以资料表放在 `private.profiles`，对外是视图 `public.profiles`：别人读到的非公开列为 `null`，`select=*` 对所有人都可用。Supabase Security Advisor 会提示「Security Definer View」，这是有意为之。封禁在 `private.profiles` 上操作。
- **`explore` 返回列**：`id, author_id, author_nickname, kind, lat, lng, locality, country_code, captured_on, width, height, image_key, thumb_key, like_count, published_at, cell_count`（列表模式 `cell_count = 1`）。网格模式最多 500 格。`min_lng > max_lng` 视为跨越 180° 经线。
- **返回值**：`upsert_profile` 返回 profiles 行；`complete_post_upload` 与 `moderate_post` 返回 `{post_id, status}`，可重复调用；`DELETE /v1/me` 返回 `{ok: true}`。
- **Worker 错误码**（`error` 字段）：`unauthorized` · `forbidden` · `banned` · `not_found` · `invalid_status` · `too_large` · `unsupported_media_type` · `bad_request` · `method_not_allowed` · `internal` · `upstream`。大小上限 1.5 MiB / 300 KiB；HEIC 只认 `ftyp` 主品牌（会拒绝 AVIF）。
- **§6 以外的 hint**（客户端 bug 或边界情况）：`not_authenticated` · `invalid_argument` · `not_found` · `invalid_status`。
- **昵称**：去掉首尾空白后 1–24 字符，不含控制字符；建资料后第一次修改不受冷却限制，之后两次修改间隔 7 天。
- **条款版本**：已同意的版本不会降低；大于当前版本的值被拒绝。
- **举报**：屏蔽了作者之后仍可举报其公开或已隐藏的帖子；`reason` 暂为 1–32 字符的自由文本（原因列表由 `add-reporting-and-blocking` 决定）。审核通过会关闭该帖的举报，拒绝则标为成立。
- **点赞每日上限** 按现存点赞行计数：取消再点不重复计数。点赞、收藏重复插入不会触发上限检查。
- **尚未覆盖**：没有设置 `avatar_post_id` 的 RPC（头像在阶段 2）；`removed` 行 30 天清理暂时手动执行（SQL 在 `server/README.md`），注意清理会让当月额度提前释放。
