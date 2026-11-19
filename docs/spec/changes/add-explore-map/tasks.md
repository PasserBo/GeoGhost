# Tasks: add-explore-map

## Now
T1–T6 完成，测试帖与临时游客已删除。2026-11-12 独立审查修复：缩到接近全球时视口取整后只剩日界线附近一条窄带（`ExploreBounds.snapped`），已修，测试 `ExploreGeometryTests.testSnappingAWideRegionCoversTheWholeWorld`。剩 me：T7 冷启动内容（在几个城市发布种子贴纸）、T8 真机浏览体验。

## M1 · 规划
- [x] T1 决定世界地图入口（新标签页 / 地图图层） — owner: me · verify: proposal Decisions · done 2026-11-12
  - evidence: 用户决定：现有地图上加「我的 / 世界」切换
- [x] T2 delta `explore-map` 与 design（缩放级别 → 网格大小、请求节流、缓存） — owner: agent · after: T1 · verify: spec_tool check-delta 无错误 + 用户确认 · done 2026-11-12
  - evidence: `specs/explore-map/spec.md`（7 条要求）check-delta 无警告；`design.md`

## M2 · 实现
- [x] T3 explore 查询客户端（视口去抖、取消过期请求、内存缓存） — owner: agent · after: T2 · verify: 单元测试 · done 2026-11-12
  - evidence: `ExploreGeometryTests`（6 个：视口换算、跨 180° 经线、全球、缩放→网格大小、取整覆盖原范围、解码服务端行）+ `ExploreModelTests`（3 个：连续拖动只请求最后一次、小范围移动走缓存、失败提示与重试）
- [x] T4 地图显示：聚合数字 / 缩略图标注，点按聚合放大 — owner: agent · after: T3 · verify: 模拟器截图 · done 2026-11-12
  - evidence: 模拟器真实后端（3 张临时测试帖，后台通过）：缩小时东京显示数量 3 的聚合，点按放大到 1/4 范围；放大到街区显示单张缩略图
- [x] T5 他人贴纸详情页 — owner: agent · after: T3 · verify: 模拟器截图 · done 2026-11-12
  - evidence: 模拟器：点单张打开详情，大图带透明、「Sticker · 渋谷区, Japan · Found on November 3, 2026 · By seed test」与 100 m 说明
- [ ] T9 在 Worker 边缘缓存匿名 explore 查询（按网格对齐视口、缓存 30–60 秒），让远离东京的用户浏览也快 — owner: agent · after: T3 · verify: 从海外节点测得的响应时间对比
- [x] T6 空区域、离线、失败的状态 — owner: agent · after: T4 · verify: 模拟器截图 · done 2026-11-12
  - evidence: 模拟器：服务器无公开贴纸时底部显示「No public pieces here yet.」；离线提示与重试由 ExploreModelTests 覆盖，UI 未实际断网触发

## M3 · 内容与验证
- [ ] T7 冷启动内容：在 3–5 个城市发布种子贴纸 — owner: me · after: add-publishing T11 · verify: 世界地图上可见
- [ ] T8 真机浏览体验（流畅度、流量） — owner: me · after: T6 · verify: 真机通过
