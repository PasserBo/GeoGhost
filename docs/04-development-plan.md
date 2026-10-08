# GeoGhost — 开发计划

> 里程碑按「可交付的产品状态」划分，而非按技术层。每个里程碑结束时 App 都应可安装、可用。
> 状态标记：☐ 未开始 · ◐ 进行中 · ☑ 完成

## M0 · 重置与脚手架（2026-09-24）

- ☑ 决策：放弃 Flutter，原生 SwiftUI 重写（ADR-001）
- ☑ 编写 PRD / 架构 / 数据模型 / 采集管线 / 上架清单
- ☑ 移除 `frontend/`（Flutter），建立 `GeoGhost/` XcodeGen 工程，iOS 17 目标，Swift 6
- ☑ SwiftData 模型 + 设计系统基础（颜色、纸张背景、StickerCard）
- ☑ 模拟器可构建并启动；真机（generic iOS）可编译
- ☑ 单元测试 12 个（元数据解析 6、ImageStore 3、SeriesMatcher 3）；其中 2 个依赖 Vision 模型在模拟器上自动跳过

## M1 · 核心闭环：拍 → 抠 → 存 → 看

- ◐ 相机：AVFoundation 会话、快门、GPS/EXIF 写入
- ◐ 相册导入 + EXIF 读取（GPS、时间、设备、镜头、朝向）
- ☑ 分割（见上）
- ◐ 手动裁切回退
- ◐ SaveSheet：类型、备注、标签、地点自动填充（反地理编码）
- ◐ 图鉴网格（透明贴纸）、详情页（抠图/原图切换、元数据、地图）
- ◐ 地图页（全部作品 + 聚合）
- ☐ 单元测试：元数据解析、ImageStore
- **验收**：真机上 10 张不同贴纸，≥ 8 张一次分割成功；快门→抠图 ≤ 1 s

## M2 · 系列与搜索

- ☑ 系列匹配改为局部特征匹配（ORB 风格 + RANSAC），用 50 件真实贴纸校准：零误配、20/27 召回；FeaturePrint 降为回退
- ☑ SeriesMatcher 自动归类；系列详情（地图连线 + 时间线）
- ◐ 手动移出系列 ☑ / 手动合并 ☐ / 灰区建议确认 ☐
- ☑ 分类器 kind 建议（VNClassifyImageRequest 关键词映射）
- ☑ 搜索（标签/地点/备注/类型/系列名）与排序（时间/类型/地点）
- ☑ 主色提取（详情页展示；排序 ☐）
- **验收**：同一贴纸 3 个地点拍摄自动归为 1 个系列，不同贴纸不误合

## M3 · 打磨与商业化

- ☑ 导出透明 PNG（免费长边 1600 px，Pro 原尺寸）/ 分享卡片 4 种样式（Field note 免费，其余 Pro；免费版带署名）
- ☑ 商业化改版（2026-10-09，见 [06](06-product-roadmap.md)）：取消 50 件上限；Pro = 卡片样式 + 去署名 + 原尺寸导出 + 创始会员；Pro 介绍页（PaywallView）
- ☑ StoreKit 2 Pro（买断、恢复购买）；本地测试用 `Config/GeoGhost.storekit`（已挂到 Run scheme）
- ☐ iCloud 私有同步（SwiftData + CloudKit，图片走 CKAsset）— **移出 v1.0**，与线上阶段一起做
- ☑ 全量导出 ZIP / 删除全部数据
- ☑ 本地化 en / zh-Hans / ja（`Localizable.xcstrings` 全部 222 条 + `InfoPlist.xcstrings` 权限文案；英文复数）
- ☐ 深色模式；Dynamic Type；VoiceOver 标签
- ☐ 空状态、加载态、错误态全覆盖
- ☐ App 图标、启动画面、截图

## M4 · 上架 v1.0

- ☐ 按 [05-app-store-checklist.md](05-app-store-checklist.md) 逐项完成
- ☐ TestFlight 内测 2 周（≥ 10 人）
- ☐ 提交审核

### v1.0 上架范围（2026-10-09 确定）

最快上架 = 本地单人图鉴 + 新的免费/Pro 划分。**不含** iCloud 同步、任何线上功能、三语以外的本地化。
上架前必须：☑ 本地化 en/zh-Hans/ja · ☐ 空/错误态 · ☐ App 图标终稿 · ☐ 截图 · ☐ 真机冒烟（相机、分割、购买）。

## v1.x · 线上（上架后）

按 [商业化与线上路线图](06-product-roadmap.md) §4 分阶段：

- ☐ 阶段 1：后端选型（倾向 Supabase）、Sign in with Apple、发布（默认私密、坐标模糊、剥 EXIF）、Explore 世界地图、点赞/灵感夹、举报/屏蔽/审核、Pro+ 订阅与创始会员兑现、iCloud 私有同步
- ☐ 阶段 2：个人主页、关注、跨用户「贴纸迁徙地图」、首位发现者
- ☐ 阶段 3：「还在吗？」、城市挑战、艺术家认领

## 已知风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 贴纸贴在杆子上时分割可能把杆子一起抠出，或 Vision 完全不返回实例 | 核心体验 | 多实例点选；长按种子点区域生长；「手动裁切」；测试集校准 |
| 手绘变体、角点稀少的极简图案局部特征匹配不上 | 漏合 | 灰区建议人工确认；后续评估加入轮廓/形状描述子 |
| 模拟器无相机、**且无 Vision 神经网络模型**（分割/FeaturePrint/分类均报 `Failed to create espresso context`） | 核心管线只能在真机验证 | 相册导入 + 手动裁切路径在模拟器可测；分割/系列匹配/分类用真机；单测遇此错误自动 skip |
| CloudKit 公共库审核对 UGC 要求（举报、屏蔽） | v1.x 上架 | 提前设计举报流程 |
