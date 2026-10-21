# GeoGhost — App Store 提交填写表（v1.0.0）

> 2026-10-19 · 按 App Store Connect 的页面顺序排列，值可直接复制。商店文案正文见 [07-store-listing.md](07-store-listing.md)。
> 前提：v1.0 免费、**无内购**、无账号、无服务器、无分析 SDK。

## 0. 已就绪（不用再做）

| 项 | 状态 |
|---|---|
| 归档 | `GeoGhost 1.0.0 (22)`，在 Mac 的 Xcode 应用 → 菜单 Window → Organizer → Archives |
| 图标 | 1024 无 alpha + 深色/着色 |
| 截图 | `AppStoreScreenshots/<语言>/6.3in/1…5.png`（1206×2622，**必需**）＋ `6.9in/`（1320×2868，选填） |
| 隐私政策 | https://passerbo.github.io/GeoGhost/privacy/ （已上线、无内购表述） |
| 支持页 | https://passerbo.github.io/GeoGhost/support/ |
| 出口合规 | Info.plist 已声明 `ITSAppUsesNonExemptEncryption = NO`，上传后不会再问 |

## 1. 新建 App（我的 App → ＋ → 新建 App）

| 字段 | 值 |
|---|---|
| 平台 | iOS |
| 名称 | GeoGhost（若被占用：`GeoGhost: Sticker Field Guide`） |
| 主要语言 | 英语（美国） |
| 套装 ID | `com.passerbo.geoghost` |
| SKU | `geoghost` |
| 用户访问权限 | 完全访问权限 |

## 2. 上传构建

在 **Mac 上的 Xcode 应用**里操作（不是 App Store Connect 网页）：菜单栏 **Window → Organizer**（或双击 `~/Library/Developer/Xcode/Archives/` 里的 .xcarchive）→ 左侧 **Archives** → 选中 **GeoGhost 1.0.0 (22)** → 右侧 **Distribute App** → **App Store Connect** → **Upload** → 一路默认（自动签名）。
上传前必须先完成 §1（网页上已建好 App 记录），否则会报找不到对应 App。
10–30 分钟后出现在 App Store Connect → TestFlight。建议先加入「内部测试」在真机装一次 TestFlight 版本再提交审核。

## 3. App 信息（左栏「App 信息」）

**本地化信息**（右上角语言菜单添加 简体中文、日语，各自填写）

| 字段 | 值 |
|---|---|
| 名称 | GeoGhost |
| 副标题 | en: Street Sticker Field Guide / zh: 街头贴纸图鉴 / ja: 街のステッカー図鑑 |

**一般信息**

| 字段 | 值 | 说明 |
|---|---|---|
| 主要语言 | English (U.S.) | 无对应本地化的地区显示它 |
| 类别 | 主：摄影与录像；次：旅游 | |
| 内容版权 | **否** | 问的是 App 本身是否含/显示/获取第三方内容（授权音乐、影视、新闻源等）。App 只显示用户自己拍的照片；地图是系统 MapKit |
| 年龄分级 | 见 §6 → 4+ | Made for Kids：**否**（选是会套用儿童类审核规则） |
| 许可协议 | Apple 标准 EULA | |
| 加密文档 | 不需要 | Info.plist 已声明豁免 |

**辅助功能营养标签（Accessibility）**：选填，**v1.0 先不填**。勾选即公开声明在常用任务中完整支持；VoiceOver / 动态字体尚未逐项验证（04 开发计划 ☐），验证后再补。

**法规与许可**：中国大陆 ICP 备案号留空（v1.0 不上中国大陆，见 §5）。

**DSA 交易商声明**（仅当销售范围含欧盟）：免费无收入可声明「非交易商」，否则地址电话会公开显示。

> 截图中的街头作品属于元数据，适用审核指南 5.2.1，与「内容版权」问题无关。已剔除动漫/商业角色、品牌与脏话；若被质疑，说明是用户在公共场所拍摄、App 为个人记录工具，或换成自己拍的无争议素材。

## 4. App 隐私（左栏「App 隐私」）

- 隐私政策网址：`https://passerbo.github.io/GeoGhost/privacy/`
- 数据收集：**「否，我们不从此 App 收集数据」**
  - 理由：照片、位置、备注只存在设备上；反地理编码由 Apple 的服务处理，不经过开发者；没有分析/广告/崩溃 SDK。

## 5. 价格与销售范围

- 价格：**免费**
- 销售范围：所有国家或地区（或至少 日本 / 中国大陆以外的简体中文区 / 美国）
  - 中国大陆上架需要 ICP 备案号（2023 年起的规定），v1.0 建议**先不勾选中国大陆**，其余地区照常。

## 6. 年龄分级问卷

全部选 **无 / 否**：
- 应用内控制（家长控制、年龄验证）：无
- 功能：不受限制的网页访问 否 · 用户生成内容 否 · 消息与聊天 否 · 广告 否
- 成人主题、暴力、恐怖、医疗、赌博、色情、药物酒精烟草、亵渎、竞赛：全部 无

→ 结果 4+。（v1.x 开放公开分享后要重答：用户生成内容 = 是）

## 7. 版本页「1.0.0 准备提交」

| 字段 | 值 |
|---|---|
| 截图 · iPhone with Dynamic Island **(medium display)** | **必需**。拖入 `AppStoreScreenshots/<语言>/6.3in/1…5.png`（1206×2622），顺序 1→5 |
| 截图 · iPhone with Dynamic Island (large display) | 选填。`6.9in/1…5.png`（1320×2868）；不传则由 medium 缩放 |
| 截图 · iPhone Duo | 现在不需要：2027 年 4 月起，用 iOS 27.1 SDK 及以上构建的 App 才要求（当前用 iOS 26.5 SDK） |
| 推广文本 / 描述 / 关键词 | 07 对应语言 |
| 技术支持网址 | `https://passerbo.github.io/GeoGhost/support/` |
| 营销网址 | 留空（docs 首页是开发文档，不适合给用户看） |
| 版本 | 1.0.0 |
| 版权 | `2026 Yiyang Xu`（与开发者账号名一致；也可用 PasserBo） |
| 构建版本 | 选 **22** |
| App 内购买项目 | 无 |

### Header and Search Results（页眉与搜索结果，2026-10 新增，选填）

- 只在 iOS 27 及以上显示；不填时搜索结果改用截图，不影响提交。
- 每种语言上传 `AppStoreScreenshots/<语言>/header.png`：**通用尺寸 5244×2950（16:9）PNG，无透明**，同时用于页眉（裁成 21:9）和搜索卡片（裁成 3:2）。
- 文字与贴纸都在两种裁切的重叠区内；上传后用 App Store Connect 的「预览」确认两种裁切。
- 由 `swift scripts/make-store-header.swift <贴纸抠图目录> AppStoreScreenshots` 生成。

### App 审核信息

- 需要登录：**否**
- 联系人：你的姓名 / 电话 / 邮箱（审核员有问题会联系）
- 备注（英文，原样粘贴）：

```
GeoGhost is a personal field guide for street stickers, graffiti and murals. No account or sign-in is needed, and there are no in-app purchases.

How to test (same steps as the HOW IT WORKS section of the description):
1. Tap Capture (the center tab) and photograph any sticker, poster, label or logo. Or tap the photo button at the bottom left of the camera screen to import a picture from the library.
2. Hold a finger on the subject to select it, or draw a loop around it. Tap "Use this cutout".
3. Tap "Save". The piece appears in Collection with its place and time.
4. Photograph or import the same design a second time; both pieces are linked under the Series tab.
5. Open a piece and use the ••• menu to create a share card or export a transparent PNG.

Location is read only while the camera screen is open and is optional. Subject detection, cutouts and matching run entirely on-device; the app has no server and collects no data.
```

### 版本发布

- **手动发布此版本**（审核通过后自己点发布，方便选时机）
- 分阶段发布：**开启**（7 天）

## 8. 提交后

- 审核通常 1–2 天。被拒时 Resolution Center 会写明条款号，把原文发给我一起改。
- 上线后看：App Analytics（留存、会话）、Xcode Organizer（崩溃、卡顿）、评分评论。数据来源说明见 [06](06-product-roadmap.md) §7.5。
- 下一个版本：改代码 → 提交（构建号自动 +1）→ Archive → Upload → 新建版本 → 选新构建。
