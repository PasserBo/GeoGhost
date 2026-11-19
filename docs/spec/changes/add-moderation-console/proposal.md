# Proposal: 一个能看图、一键处理的审核后台

> State: in-progress · Updated: 2026-11-12

## Intent
UGC 上架要求每条举报 24 小时内处理（审核指南 1.2），新用户的前 3 张也要人工审核。现在只能在 Supabase SQL Editor 里查 id、手写 `moderate_post`，而且**看不到图片**，审核既慢又容易出错。一个人运营时，审核必须能在手机上几十秒处理完一条。衡量：待审核最久的一条始终不超过 24 小时。

## Scope
In scope:
- 待审核队列（最早的在前）：抠图大图、区域、日期、类型、发布者昵称，以及发布者的历史（通过 / 未通过次数、是否被举报过）。
- 被举报 / 自动隐藏的帖子：举报原因与说明、举报人数。
- 操作：通过、拒绝、删除（连图片）、封禁发布者 / 解除封禁；每次操作记录谁在何时做了什么。
- 顶部显示待处理数量和最久一条已等待多久。
- 手机浏览器上可用。
- 只有开发者本人能打开。
Out of scope:
- 多名审核员的分工与权限分级。
- 自动审核（图像识别过滤）。
- 申诉流程（仍走支持页邮件）。

## Capabilities
- `moderation-console` (new) — 使用者是开发者（运营者），不是 App 用户。

## Approach
单独一个 Worker（`geoghost-admin`），不和公开的 `geoghost-api` 混在一起；前面用 Cloudflare Access 挡住，只放行开发者的邮箱。页面由 Worker 直接输出 HTML，图片从 R2 直接读，数据用 service role 调数据库。

## Decisions
- 2026-11-12: 提出 — 用户认为有必要在 Worker 里做一个简易审核后台，替代 SQL Editor。
- 2026-11-12: 决定做，按推荐方案：独立 Worker `geoghost-admin` + Cloudflare Access 登录（只放行开发者邮箱） — 不自己存密码和会话，管理接口不出现在 App 能访问的地址上。

- 2026-11-12: Access 策略用「Cloudflare account members」（workers.dev 一键开启的选项），Worker 再用邮箱白名单（Cloudflare 账号邮箱）做第二道检查 — 两层都要通过。
- 2026-11-12: 图片在浏览器里用 libheif 解码显示 — 用户觉得只能用 Safari 太麻烦；不改 App 的上传格式，也不占服务器 CPU。

## Open questions
- 新举报 / 待审核的通知是否一起做（`add-reporting-and-blocking` T5），通知里直接带审核页链接。

## Links
- 后端契约: [setup-online-backend/design.md](../setup-online-backend/design.md) §5 `moderate_post`、§10 · 举报: [add-reporting-and-blocking](../add-reporting-and-blocking/proposal.md)
