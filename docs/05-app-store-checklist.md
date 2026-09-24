# GeoGhost — App Store 上架清单

## 账号与标识
- ☐ Bundle ID：`com.passerbo.geoghost`（Team `J95TRWHWYM`）
- ☐ App Store Connect 建立 App，名称 **GeoGhost**，副标题「Street Sticker Field Guide」
- ☐ 类别：主 Photo & Video，次 Travel
- ☐ 年龄分级：4+（无 UGC 展示，v1）
- ☐ 内购：`com.passerbo.geoghost.pro`（非消耗型）
- ☐ iCloud 容器：`iCloud.com.passerbo.geoghost`

## 技术
- ☐ Info.plist 权限文案（相机、位置使用时、相册仅添加）三语
- ☐ `PrivacyInfo.xcprivacy` 清单
- ☐ 隐私营养标签：位置（关联到用户，仅功能）、照片（不离开设备）、无追踪
- ☐ 支持 iPhone 竖屏；iPad 以兼容模式运行（v1 不做 iPad 专属布局）
- ☐ 无崩溃：TestFlight 崩溃率 < 0.5%
- ☐ 冷启动 ≤ 1.5 s（Instruments 验证）
- ☐ 深色模式/Dynamic Type 检查
- ☐ 移除所有 `print` 调试输出，改为 `Logger`

## 审核指南要点
- 2.1 完整性：所有按钮有功能；空状态有内容
- 3.1.1 内购只用 StoreKit；有「恢复购买」入口
- 5.1.1 数据收集：位置仅在拍摄时；提供删除全部数据
- 5.1.2 不与第三方共享数据
- 5.2.1 版权：App 描述定位为个人图鉴/笔记；不声称作品归属
- 审核备注：说明相机在审核设备上如何测试（附带示例照片可导入）

## 素材
- ☐ 图标 1024×1024（无 alpha）
- ☐ 截图 6.9"（1320×2868）与 6.5"（1284×2778）各 5 张：采集分割、图鉴、系列地图、详情、地图
- ☐ 预览视频（可选）
- ☐ 隐私政策 URL、支持 URL（GitHub Pages 即可）
- ☐ 描述、关键词、What's New（en / zh-Hans / ja）

## 发布
- ☐ 版本 1.0.0 (1)，Release 配置 `-O`、strip
- ☐ TestFlight 外测 ≥ 2 周
- ☐ 分阶段发布 7 天
