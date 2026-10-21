# GeoGhost — App Store 上架清单

## 账号与标识
- ☐ Bundle ID：`com.passerbo.geoghost`（Team `J95TRWHWYM`）
- ☐ App Store Connect 建立 App，名称 **GeoGhost**，副标题「Street Sticker Field Guide」
- ☐ 类别：主 Photo & Video，次 Travel
- ☐ 年龄分级：4+（无 UGC 展示，v1）
- ~~内购 `com.passerbo.geoghost.pro`~~ —— **v1.0 不开内购**（2026-10-14），开放时再建，见 [06](06-product-roadmap.md) 阶段 0.5
- ☐ iCloud 容器：`iCloud.com.passerbo.geoghost`（v1.0 不需要，线上阶段再建）

## 技术
- ◐ Info.plist 权限文案（相机、位置使用时、相册仅添加）— 三语完成 ☑
- ☑ `PrivacyInfo.xcprivacy` 清单
- ☐ 隐私营养标签：**「不收集数据」**（v1.0 无服务器、无分析；数据只在设备上，反地理编码由 Apple 处理）
- ☑ 支持 iPhone 竖屏；iPad 以兼容模式运行（`TARGETED_DEVICE_FAMILY = 1`，因此不需要 iPad 截图）
- ☐ 无崩溃：TestFlight 崩溃率 < 0.5%
- ☐ 冷启动 ≤ 1.5 s（Instruments 验证）
- ☐ 深色模式/Dynamic Type 检查
- ☐ 移除所有 `print` 调试输出，改为 `Logger`

## 审核指南要点
- 2.1 完整性：所有按钮有功能；空状态有内容
- 3.1.1 内购只用 StoreKit；有「恢复购买」入口（v1.0 无内购，开放 Pro 时适用）
- 5.1.1 数据收集：位置仅在拍摄时；提供删除全部数据
- 5.1.2 不与第三方共享数据
- 5.2.1 版权：App 描述定位为个人图鉴/笔记；不声称作品归属
- 审核备注：说明相机在审核设备上如何测试（附带示例照片可导入）

## 素材
- ☑ 图标 1024×1024（无 alpha）+ 深色 / 着色变体，由 `scripts/make-app-icon.swift` 生成
- ☑ 截图 5 张 × 3 语言：图鉴、详情、系列路线、地图、分享卡片。**必需尺寸是 iPhone with Dynamic Island (medium display) 1206×2622**（2026-10 核对 Apple 规格；之前以为只要 6.9" 是错的，上传会报 File dimensions are invalid）；6.9" 1320×2868 选填。iPhone Duo 截图自 2027-04 起对 iOS 27.1 SDK+ 构建必需
  - 成品在项目根目录 `AppStoreScreenshots/<语言>/{6.3in,6.9in}/1…5.png`（git 忽略：含第三方街头作品与真实拍摄地点）
  - 流程：Debug 构建用 `-seedExport <导出目录>` 导入精选导出（`DebugSeeder`，只在 Debug 编译）→ 专用模拟器「GeoGhost Shots」(iPhone 17 Pro Max) 截原图 → `swift scripts/compose-screenshots.swift <raw> AppStoreScreenshots` 加标题合成
  - 素材取舍：只用匿名街头作者的贴纸，剔除动漫/商业角色、品牌 logo、脏话；坐标取整到约 100 m
- ☐ 预览视频（可选）
- ☑ 隐私政策 URL https://passerbo.github.io/GeoGhost/privacy/ · 支持 URL https://passerbo.github.io/GeoGhost/support/（GitSpec 构建的 GitHub Pages，仓库已公开）
- ◐ 描述、关键词、推广文本（en / zh-Hans / ja）：草稿见 [07-store-listing.md](07-store-listing.md)，待填入 App Store Connect

## 发布
- ☑ 版本 1.0.0，构建号 = git 提交数自动生成；Release 归档验证通过
- ☐ TestFlight 外测 ≥ 2 周
- ☐ 分阶段发布 7 天

## TestFlight → 上架流程

> 逐字段的填写值见 [08-app-store-submission.md](08-app-store-submission.md)。

> ☐ 标 **[你]** 的步骤需要本人在 App Store Connect / Xcode 中操作（涉及账号、协议、付款信息）。

### 1. 一次性准备
1. **[你]** App Store Connect → 协议、税务和银行业务：确认**免费 App 协议**有效（加入开发者计划时已自动接受；v1.0 免费、无内购，不需要付费协议和银行/税务）。
2. **[你]** 我的 App → 新建 App：平台 iOS、名称 GeoGhost、主语言英文、Bundle ID `com.passerbo.geoghost`、SKU `geoghost`。
3. ~~App 内购买项目~~ —— v1.0 跳过。
4. **[你]** App 隐私：填「不收集数据」；隐私政策 URL https://passerbo.github.io/GeoGhost/privacy/ 。
5. ~~沙盒测试员~~ —— 开放 Pro 时再建。

### 2. 每次上传构建
1. 提交代码（构建号 = 提交数，必须比上一次大）。
2. Xcode：Scheme GeoGhost、目标 **Any iOS Device (arm64)** → Product → Archive。
3. Organizer → Distribute App → **App Store Connect** → Upload（自动签名）。
4. 约 10–30 分钟后出现在 App Store Connect → TestFlight，状态「处理中」→「可测试」。出口合规已在 Info.plist 声明（`ITSAppUsesNonExemptEncryption = NO`），不会再问。

### 3. TestFlight
1. **内部测试**（最多 100 名团队成员，无需审核）：TestFlight → 内部测试 → 新建群组 → 加入构建。自己先在真机上走一遍：拍照→抠图→保存、系列、地图、分享卡片、导出 PNG / ZIP、删除全部数据。
2. **外部测试**（最多 1 万人，首个构建需 Beta App Review，通常 1 天内）：新建外部群组 → 填「测试内容」与反馈邮箱 → 开**公开链接** → 发给种子用户（贴纸爱好者社群、朋友）。目标 ≥ 10 人、≥ 2 周。
3. 每轮看 TestFlight 的崩溃与反馈截图；有改动就再上传一个构建（外部群组后续构建通常免审或很快）。

### 4. 提交审核
1. **[你]** App 信息：副标题、类别、年龄分级问卷（v1.0 无 UGC → 4+）、版权。
2. **[你]** 版本页：截图、描述、关键词、推广文本、支持 URL、What's New；三种语言。
3. 选择构建（v1.0 无内购，不需要勾选任何 App 内购买项目）。
4. 审核备注：说明无需登录、无内购；相机可用任意贴纸/海报测试，也可从相册导入。
5. 发布方式：**手动发布** + **分阶段发布 7 天**。

### 5. 上架后
- 监控崩溃（Xcode Organizer → Crashes）、评分、留存与会话（App Store Connect → App Analytics），数据来源见 [06](06-product-roadmap.md) §7.5。
- 按 [06](06-product-roadmap.md) 的指标决定价格和线上阶段的启动时间。
