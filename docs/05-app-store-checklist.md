# GeoGhost — App Store 上架清单

## 账号与标识
- ☐ Bundle ID：`com.passerbo.geoghost`（Team `J95TRWHWYM`）
- ☐ App Store Connect 建立 App，名称 **GeoGhost**，副标题「Street Sticker Field Guide」
- ☐ 类别：主 Photo & Video，次 Travel
- ☐ 年龄分级：4+（无 UGC 展示，v1）
- ☐ 内购：`com.passerbo.geoghost.pro`（非消耗型，价格见 [06](06-product-roadmap.md) §6），含审核截图（Pro 介绍页）与审核备注
- ☐ iCloud 容器：`iCloud.com.passerbo.geoghost`（v1.0 不需要，线上阶段再建）

## 技术
- ◐ Info.plist 权限文案（相机、位置使用时、相册仅添加）— 英文完成，三语 ☐
- ☑ `PrivacyInfo.xcprivacy` 清单
- ☐ 隐私营养标签：**「不收集数据」**（v1.0 无服务器、无分析；数据只在设备上，反地理编码由 Apple 处理）
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
- ☑ 隐私政策 URL https://passerbo.github.io/GeoGhost/privacy/ · 支持 URL https://passerbo.github.io/GeoGhost/support/（GitSpec 构建的 GitHub Pages，仓库已公开）
- ☐ 描述、关键词、What's New（en / zh-Hans / ja）

## 发布
- ☑ 版本 1.0.0，构建号 = git 提交数自动生成；Release 归档验证通过
- ☐ TestFlight 外测 ≥ 2 周
- ☐ 分阶段发布 7 天

## TestFlight → 上架流程

> ☐ 标 **[你]** 的步骤需要本人在 App Store Connect / Xcode 中操作（涉及账号、协议、付款信息）。

### 1. 一次性准备
1. **[你]** App Store Connect → 协议、税务和银行业务：签署**付费 App 协议**并填好银行/税务（不签内购无法上架，沙盒也可能取不到产品）。
2. **[你]** 我的 App → 新建 App：平台 iOS、名称 GeoGhost、主语言英文、Bundle ID `com.passerbo.geoghost`、SKU `geoghost`。
3. **[你]** App 内购买项目 → 新建**非消耗型** `com.passerbo.geoghost.pro`：参考名称 GeoGhost Pro、价格、en/zh-Hans/ja 显示名与描述、审核截图（Pro 介绍页）。
4. **[你]** App 隐私：填「不收集数据」；隐私政策 URL https://passerbo.github.io/GeoGhost/privacy/ 。
5. **[你]** 用户和访问 → 沙盒测试员：建一个沙盒 Apple ID，真机 设置 → App Store → 沙盒账户 登录，用来测购买/恢复。

### 2. 每次上传构建
1. 提交代码（构建号 = 提交数，必须比上一次大）。
2. Xcode：Scheme GeoGhost、目标 **Any iOS Device (arm64)** → Product → Archive。
3. Organizer → Distribute App → **App Store Connect** → Upload（自动签名）。
4. 约 10–30 分钟后出现在 App Store Connect → TestFlight，状态「处理中」→「可测试」。出口合规已在 Info.plist 声明（`ITSAppUsesNonExemptEncryption = NO`），不会再问。

### 3. TestFlight
1. **内部测试**（最多 100 名团队成员，无需审核）：TestFlight → 内部测试 → 新建群组 → 加入构建。自己先在真机上走一遍：拍照→抠图→保存、系列、地图、分享卡片、沙盒购买、恢复购买、删除全部数据。
2. **外部测试**（最多 1 万人，首个构建需 Beta App Review，通常 1 天内）：新建外部群组 → 填「测试内容」与反馈邮箱 → 开**公开链接** → 发给种子用户（贴纸爱好者社群、朋友）。目标 ≥ 10 人、≥ 2 周。
3. 每轮看 TestFlight 的崩溃与反馈截图；有改动就再上传一个构建（外部群组后续构建通常免审或很快）。

### 4. 提交审核
1. **[你]** App 信息：副标题、类别、年龄分级问卷（v1.0 无 UGC → 4+）、版权。
2. **[你]** 版本页：截图、描述、关键词、推广文本、支持 URL、What's New；三种语言。
3. 选择构建；在「App 内购买项目」处**勾选 Pro 一起提交**（首个内购必须随版本提交）。
4. 审核备注：说明无需登录；相机可用任意贴纸/海报测试，也可从相册导入；Pro 在 设置 → Pro 或分享卡片中购买。
5. 发布方式：**手动发布** + **分阶段发布 7 天**。

### 5. 上架后
- 监控崩溃（Xcode Organizer → Crashes）、评分、内购转化（App Store Connect → 销售趋势）。
- 按 [06](06-product-roadmap.md) 的指标决定价格和线上阶段的启动时间。
