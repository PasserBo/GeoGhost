# Proposal: 举报不当内容、屏蔽用户，并在 24 小时内处理

> State: accepted · Updated: 2026-11-12

## Intent
UGC 上架的硬性要求（审核指南 1.2），也是社区不被少数人毁掉的底线。任何人都能举报贴纸、屏蔽发布者；被多人举报的内容先自动隐藏；开发者 24 小时内处理每一条举报。

## Scope
In scope:
- 举报贴纸（选择原因，可附说明）；同一人对同一贴纸只算一次。
- 屏蔽发布者：立即看不到对方的所有贴纸；设置中可查看并解除屏蔽。
- 被不同用户举报达到门槛时自动隐藏，等待处理。
- 发布者看到自己的贴纸「未通过」。
- 开发者收到新举报与待审核的通知，并有处理流程（通过 / 隐藏 / 封禁）。
- 被封禁的用户不能再发布，其公开内容对他人不可见。
Out of scope:
- App 内审核后台（先用 Supabase 控制台 + SQL）。
- 申诉流程（先通过支持页邮件）。
- 设备级封禁、设备断言（之后评估）。

## Capabilities
- `content-safety` (new)

## Decisions
- 2026-11-11: 举报每天 20 次；3 个不同举报人自动隐藏（09 §4–§6）。

## Open questions
- 举报原因列表（色情、暴力、仇恨、个人信息、垃圾内容、其他？）。
- 开发者通知走哪条路：复用 TestFlight 反馈的 triage 管道，还是邮件。

## Links
- 后端契约: [setup-online-backend/design.md](../setup-online-backend/design.md) §5 `report_post`、`moderate_post`
