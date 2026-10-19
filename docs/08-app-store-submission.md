# GeoGhost — App Store 提交填写表（v1.0.0）

> 2026-10-19 · 按 App Store Connect 的页面顺序排列，值可直接复制。商店文案正文见 [07-store-listing.md](07-store-listing.md)。
> 前提：v1.0 免费、**无内购**、无账号、无服务器、无分析 SDK。

## 0. 已就绪（不用再做）

| 项 | 状态 |
|---|---|
| 归档 | `GeoGhost 1.0.0 (22)`，在 Mac 的 Xcode 应用 → 菜单 Window → Organizer → Archives |
| 图标 | 1024 无 alpha + 深色/着色 |
| 截图 | `AppStoreScreenshots/{en,zh-Hans,ja}/1…5.png`，6.9"（1320×2868），只需这一个尺寸 |
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

| 字段 | 值 |
|---|---|
| 副标题 | 见 07（en: Street Sticker Field Guide / zh: 街头贴纸图鉴 / ja: 街のステッカー図鑑） |
| 类别 | 主要：摄影与录像（Photo & Video）；次要：旅游（Travel） |
| 内容版权 | **否**，不包含/显示/访问第三方内容（App 只显示用户自己拍的照片） |
| 年龄分级 | 见 §6，结果 **4+** |
| 本地化 | 右上角语言菜单添加 **简体中文**、**日语**，各自填名称与副标题 |

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
| 截图（6.9"） | 按语言拖入 `AppStoreScreenshots/<语言>/1…5.png`，顺序 1→5 |
| 推广文本 / 描述 / 关键词 | 07 对应语言 |
| 技术支持网址 | `https://passerbo.github.io/GeoGhost/support/` |
| 营销网址 | 留空（docs 首页是开发文档，不适合给用户看） |
| 版本 | 1.0.0 |
| 版权 | `2026 Yiyang Xu`（与开发者账号名一致；也可用 PasserBo） |
| 构建版本 | 选 **22** |
| App 内购买项目 | 无 |

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
