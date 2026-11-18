# Design: add-update-gate-and-switches

## 配置（新迁移）

`public.app_config`，单行，`anon` / `authenticated` 只读（RLS select 全部放行，写入只经 service-role 函数）：

| 列 | 类型 | 说明 |
|---|---|---|
| `min_online_version` | text | 低于它的 App 停用线上功能，如 `1.1.0` |
| `latest_version` | text | 用于「有新版本」轻提示 |
| `publishing_enabled` | boolean | false = 暂停发布 |
| `signups_enabled` | boolean | false = 暂停新用户加入（第一次设置昵称） |
| `notice` | jsonb | 可选公告 `{"en": "...", "ja": "...", "zh-Hans": "..."}` |
| `updated_at` | timestamptz | |

版本比较按 `major.minor.patch` 数字逐段比较（SQL 与 Swift 同一规则，各自有测试）。

## 服务端执行

- 客户端所有请求（PostgREST 与 Worker）带 `X-GeoGhost-Version: <CFBundleShortVersionString>`。
- 写入类 RPC（`create_post`、`upsert_profile`、`report_post`，以及 likes / saves / blocks 的插入触发器视情况）读取 `current_setting('request.headers', true)::json->>'x-geoghost-version'`：低于 `min_online_version` → hint `update_required`；缺少头视为过低（1.1 起都会带）。
- `create_post`：`publishing_enabled = false` → hint `publishing_paused`。
- `upsert_profile` 第一次创建资料：`signups_enabled = false` → hint `signups_paused`（已有资料的人改昵称不受影响）。
- Worker（`server/worker`）上传与删除：同样检查头，过低返回 426 `{"error":"update_required"}`。删除我的线上数据**不受**版本限制（用户必须总能删除数据）。
- 读取（`explore`、公开帖子）不做版本限制：旧版本停用浏览是由客户端根据配置做的，服务端不必为读付出成本。

## 客户端

- `AppConfigService`：启动与回到前台时读取（缓存 10 分钟，上次结果存 UserDefaults）；失败沿用上次；从未成功则视为放行。
- 状态：`ok` / `updateAvailable` / `updateRequired`；外加 `publishingPaused`、`signupsPaused`、`notice`。
- `updateRequired`：世界地图切换、发布入口、举报 / 屏蔽、设置 → 线上都显示「需要更新才能使用线上功能」+ App Store 按钮（`https://apps.apple.com/app/id<appId>`），不发请求。
- 服务端返回 `update_required` / `publishing_paused` / `signups_paused` 时映射为新的 `OnlineRefusal`，文案说明原因（不再落到「额度用完」）。
- `updateAvailable`：设置 → 线上一行轻提示。
- `notice`：按当前语言显示在世界地图底部与发布预览里（无对应语言用 en）。

## 审核后台

- 新页「设置」：编辑上述字段，保存走 service-role 函数 `admin_set_app_config(..., actor)`，写入 `moderation_log`（action `config`）。
- 表单同样走同源 POST + 外部脚本确认（CSP 不允许内联脚本）。
