# Proposal: 给别人的贴纸点赞，收藏到灵感夹

> State: accepted · Updated: 2026-11-12

## Intent
浏览之外要有最轻的参与方式：点赞给发现者正反馈，灵感夹让用户留住喜欢的贴纸、下次去找。也是游客身份第一次被静默创建的最常见时机。

## Scope
In scope:
- 在贴纸详情点赞 / 取消点赞，显示点赞数。
- 收藏到灵感夹 / 移出；灵感夹列表；灵感夹上限（免费 50 张）。
- 被收藏的贴纸撤回或隐藏后，在灵感夹里的表现。
Out of scope:
- 灵感夹分组（Pro+）。
- 通知发布者「有人点赞」。

## Capabilities
- `reactions` (new)

## Decisions
- 2026-11-11: 每天点赞 300 次只为防刷；灵感夹免费 50 张（06 §5，09 §4）。

## Open questions
- 灵感夹入口放在哪（收藏页的分段 / 设置 / 世界地图）。

## Links
- 后端契约: [setup-online-backend/design.md](../setup-online-backend/design.md) §5
