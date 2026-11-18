# Proposal: 第一次打开就知道做什么，不在街上也能收下第一件

> State: in-progress · Updated: 2026-11-19

## Intent
新用户打开 App，第一眼是「是否分享诊断报告」的弹窗；空图鉴只给「去拍」一条路，而大多数人安装时眼前没有贴纸；第一次点采集会连续弹相机和定位两个系统权限，没有任何说明，拒绝定位后地图一直是空的且不知道原因；地图 tab 默认是自己的空地图，世界地图藏在分段控件里。衡量：首次打开到第一件收藏（从相册）≤ 60 秒；定位允许率（问 TestFlight 测试员 / 将来 App 内统计）提高。

## Scope
In scope:
- 图鉴空状态给出同等的两条路：拍一张、从相册选一张（不需要相册权限）；以及示例照片入口（练习本身见 [add-cutout-coaching](../add-cutout-coaching/proposal.md)）。
- 定位不再和相机一起在打开取景框时就问，而是在第一次按快门前、带一句 App 自己的说明（记录这件作品是在哪里遇到的）。
- 诊断报告同意推迟到第一件作品保存之后。
- 地图 tab 默认显示世界地图（所有用户，不只新用户）；App 运行期间记住用户切换的地图，App 重新启动后回到世界地图；线上功能不可用时显示我的地图。
- 地图和系列的空状态说明下一步能做什么。
- 第一张照片没拿到定位时，保存单可以「用我当前的位置」。
Out of scope:
- 多页欢迎轮播、账号注册（线上身份仍按 add-guest-identity 的时机）。
- 相册批量识别导入（[add-library-scan-import](../add-library-scan-import/proposal.md)）。
- 世界地图的种子内容（[add-explore-map](../add-explore-map/proposal.md) T7）。

## Capabilities
- `first-run` (new)

## Decisions
- 2026-11-19: 方向认可（me：「every single of these ideas looks great」）。
- 2026-11-19: 地图 tab 对所有用户默认显示世界地图（me：「Always use global map as the default」），不等种子内容；线上功能不可用时显示我的地图。
- 2026-11-19: 诊断报告同意在第一件作品保存之后再问。
- 2026-11-19: 第一张照片没拿到定位时，保存单提供「用我当前的位置」。
- 2026-11-19: 开放问题回答完，转 accepted。
- 2026-11-19: 用户切换地图后，App 运行期间记住这次选择；App 重新启动后回到世界地图（me：「remember last choice, but if app relaunched, world map as default」）。

## Open questions
- （无）

## Links
- 调研: [onboarding-and-cutout.md](../../../research/onboarding-and-cutout.md) §1、§4.1 · 路线图: [06 §7 冷启动](../../../06-product-roadmap.md)
