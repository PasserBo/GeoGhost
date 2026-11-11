# Tasks: add-explore-map

## Now
T3 查询客户端已完成（`GeoGhost/Services/Explore/`），与入口位置无关。等 me 决定 T1 入口，然后写 delta（T2）并接界面（T4–T6）。

## M1 · 规划
- [ ] T1 决定世界地图入口（新标签页 / 地图图层） — owner: me · verify: proposal Decisions
- [ ] T2 delta `explore-map` 与 design（缩放级别 → 网格大小、请求节流、缓存） — owner: agent · after: T1 · verify: spec_tool check-delta 无错误 + 用户确认

## M2 · 实现
- [x] T3 explore 查询客户端（视口去抖、取消过期请求、内存缓存） — owner: agent · after: T2 · verify: 单元测试 · done 2026-11-12
  - evidence: `ExploreGeometryTests`（6 个：视口换算、跨 180° 经线、全球、缩放→网格大小、取整覆盖原范围、解码服务端行）+ `ExploreModelTests`（3 个：连续拖动只请求最后一次、小范围移动走缓存、失败提示与重试）
- [ ] T4 地图显示：聚合数字 / 缩略图标注，点按聚合放大 — owner: agent · after: T3 · verify: 模拟器截图
- [ ] T5 他人贴纸详情页 — owner: agent · after: T3 · verify: 模拟器截图
- [ ] T9 在 Worker 边缘缓存匿名 explore 查询（按网格对齐视口、缓存 30–60 秒），让远离东京的用户浏览也快 — owner: agent · after: T3 · verify: 从海外节点测得的响应时间对比
- [ ] T6 空区域、离线、失败的状态 — owner: agent · after: T4 · verify: 模拟器截图

## M3 · 内容与验证
- [ ] T7 冷启动内容：在 3–5 个城市发布种子贴纸 — owner: me · after: add-publishing T11 · verify: 世界地图上可见
- [ ] T8 真机浏览体验（流畅度、流量） — owner: me · after: T6 · verify: 真机通过
