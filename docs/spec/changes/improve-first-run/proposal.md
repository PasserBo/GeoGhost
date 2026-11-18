# Proposal: 第一次打开就知道做什么，不在街上也能收下第一件

> State: idea · Updated: 2026-11-19

## Intent
新用户打开 App，第一眼是「是否分享诊断报告」的弹窗；空图鉴只给「去拍」一条路，而大多数人安装时眼前没有贴纸；第一次点采集会连续弹相机和定位两个系统权限，没有任何说明，拒绝定位后地图一直是空的且不知道原因；地图 tab 默认是自己的空地图，世界地图藏在分段控件里。衡量：首次打开到第一件收藏（从相册）≤ 60 秒；定位允许率（问 TestFlight 测试员 / 将来 App 内统计）提高。

## Scope
In scope:
- 图鉴空状态给出同等的两条路：拍一张、从相册选一张（不需要相册权限）；以及示例照片入口（练习本身见 [add-cutout-coaching](../add-cutout-coaching/proposal.md)）。
- 定位不再和相机一起在打开取景框时就问，而是在第一次按快门前、带一句 App 自己的说明（记录这件作品是在哪里遇到的）。
- 诊断报告同意推迟到第一件作品保存之后（或下一次启动）。
- 地图和系列的空状态说明下一步能做什么；收藏为空且线上功能可用时，地图先显示世界地图。
Out of scope:
- 多页欢迎轮播、账号注册（线上身份仍按 add-guest-identity 的时机）。
- 相册批量识别导入（[add-library-scan-import](../add-library-scan-import/proposal.md)）。
- 世界地图的种子内容（[add-explore-map](../add-explore-map/proposal.md) T7）。

## Capabilities
- `first-run` (new)

## Decisions
- 2026-11-19: 方向认可（me：「every single of these ideas looks great」）— 状态仍是 idea，开放问题回答后再转 accepted。

## Open questions
1. 收藏为空时地图默认显示世界地图，是否要等种子内容上线后再开？（选项：a 种子内容上线后再开 / b 现在就开 / c 不改默认）
2. 诊断同意推迟到什么时候？（选项：a 第一件作品保存后 / b 第二次启动 / c 只在设置里，不主动问）
3. 第一张照片拍完时定位还没拿到（刚允许），保存单是否提供「补上当前位置」？（选项：a 提供 / b 保持现在：无地点，详情页可手动放）

## Links
- 调研: [onboarding-and-cutout.md](../../../research/onboarding-and-cutout.md) §1、§4.1 · 路线图: [06 §7 冷启动](../../../06-product-roadmap.md)
