# Proposal: 游客绑定 Apple 账号，换机也能找回

> State: accepted · Updated: 2026-11-12

## Intent
游客身份只保存在一台手机上，换机或抹掉手机就会失去对自己发布内容的管理。绑定 Apple 账号后同一身份可以在新手机上找回，发布、点赞、收藏全部保留。阶段 2 的关注和徽章让身份更值钱，所以要在阶段 2 之前完成。

## Scope
In scope:
- 设置页绑定 Apple 账号；绑定后在新手机上用 Apple 登录找回。
- 在「有东西可能丢」的时机提示绑定（09 §5），可关闭，至少间隔 14 天。
- 删除账号。
Out of scope:
- 其他登录方式。
- 解绑回游客。

## Capabilities
- `online-identity` (modified)

## Decisions
- 2026-11-11: 绑定不改变身份，帖子不迁移；注册不解锁功能、不提高额度（09 §1）。

## Links
- Design: [09](../../../09-online-identity.md) §2、§5
