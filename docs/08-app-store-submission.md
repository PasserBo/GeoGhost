# GeoGhost — App Store 提交填写表（v1.0.0）

> 2026-10-19 · 按 App Store Connect 的页面顺序排列，值可直接复制。商店文案正文见 [07-store-listing.md](07-store-listing.md)。
> 前提：v1.0 免费、**无内购**、无账号、无服务器、无分析 SDK。

## 0. 已就绪（不用再做）

| 项 | 状态 |
|---|---|
| 归档 | `GeoGhost 1.0.0 (22)`，在 Mac 的 Xcode 应用 → 菜单 Window → Organizer → Archives |
| 图标 | 1024 无 alpha + 深色/着色 |
| 截图 | `AppStoreScreenshots/<语言>/1…5.png`（1206×2622，iPhone with Dynamic Island (medium display)，唯一需要的尺寸） |
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
| 截图 · iPhone with Dynamic Island (medium display) | 拖入 `AppStoreScreenshots/<语言>/1…5.png`（1206×2622），顺序 1→5。App Store Connect 已不再提供 large display 栏位 |
| 截图 · iPhone Duo | 现在不需要：2027 年 4 月起，用 iOS 27.1 SDK 及以上构建的 App 才要求（当前用 iOS 26.5 SDK） |
| 推广文本 / 描述 / 关键词 | 07 对应语言 |
| 技术支持网址 | `https://passerbo.github.io/GeoGhost/support/` |
| 营销网址 | 留空（docs 首页是开发文档，不适合给用户看） |
| 版本 | 1.0.0 |
| 版权（必填） | `2026 Yiyang Xu`：年份＋权利人，**不要输入 ©**（商店自动加）。只有一个值，不随语言变化。也可填 `2026 PasserBo Studio`，但它目前不是法人，严格来说权利人是你本人 |
| 构建版本 | 选 **22** |
| App 内购买项目 | 无 |

### Header and Search Results（页眉与搜索结果，2026-10 新增，选填）

- 只在 iOS 27 及以上显示；不填时搜索结果改用截图，不影响提交。
- 每种语言上传 `AppStoreScreenshots/<语言>/header.png`：**通用尺寸 5244×2950（16:9）PNG，无透明**，同时用于页眉（裁成 21:9）和搜索卡片（裁成 3:2）。
- 三种裁切（Apple 未公开，按 Device Preview 实测）：**iPhone 产品页**＝顶部对齐、水平居中的约 3:2 窗口（约 x 1250–4100、y 0–1900），上三分之一被状态栏和返回/分享按钮遮住；**搜索卡片**＝整张图；**iPad/Mac 产品页**＝中间 21:9 横条。标语和主贴纸放在 iPhone 窗口按钮以下，其余贴纸填充外围。上传后务必在「预览」里切换 Product Page / Search Results 再确认。
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

## 9. 1.1.0（线上功能）提交前要改的项

> 2026-11-12 起草（prepare-ugc-release T2、T4）。提交前对照 App Store Connect 当时的选项再确认一遍。

### 9.1 App 隐私

- 隐私政策网址不变；内容已更新（docs/privacy.md「Online features」一节），2026-11-19 已在 main 上线。
- 数据收集改为「**是**」。全部**不用于跟踪**。线上数据都挂在匿名游客 ID 上，所以选「**与用户身份关联**」；诊断数据不含任何标识，选「不关联」。
- 用途：凡是会被汇总起来评估功能效果、规划新功能的，都同时勾「**分析**」：用户 ID、发布的抠图、粗略位置（阶段 1 成功指标，06 §8）；诊断数据（TestFlight / 崩溃报告经 triage 管道汇总后生成改进提案，也用于统计抠图失败等）；客户支持（反馈里的想法用于规划路线图）。只有昵称、举报说明只用于展示与审核，只勾「App 功能」。

| 类别 › 类型 | 内容 | 用途 | 关联身份 |
|---|---|---|---|
| 标识符 › 用户 ID | 匿名游客 ID（Supabase 匿名账号，凭证存本机 Keychain） | App 功能、**分析** | 是 |
| 用户内容 › 照片或视频 | 用户主动发布的抠图 | App 功能、**分析** | 是 |
| 位置 › 粗略位置 | 发布时约 100 m 的模糊位置 | App 功能、**分析** | 是 |
| 用户内容 › 其他用户内容 | 昵称、举报原因与说明 | App 功能 | 是 |
| 诊断 › 崩溃数据、性能数据、其他诊断数据 | 用户同意后才发送的崩溃 / 错误报告（1.0.1 起） | App 功能、**分析** | 否 |
| 用户内容 › 客户支持 | 设置里发送的反馈（可附截图与邮箱） | App 功能、**分析** | 否 |

- **标识符 › 设备 ID：否**。代码里没有 IDFA、IDFV（identifierForVendor）、DeviceCheck、App Attest；崩溃报告只有机型。以后加 App Attest / DeviceCheck 封禁设备时重新评估。
- 以后在 App 里上报 `ui/event.yaml` 的行为事件时，新增「使用数据 › 产品交互」（用途：分析，关联：视实现而定）。
- 不收集：精确位置、原照片、联系方式（邮箱只在用户自己填写反馈时发送，归在客户支持）、使用数据、购买。

### 9.2 年龄分级问卷

> 2026-11-19 按 Apple 的定义（App Store Connect Help › Age ratings）重写：只勾「用户生成内容」时结果仍是 4+，因为这一项本身对应 4+。

- **功能 › 用户生成内容：是**（4+）。
- **功能 › 社交媒体：是**（13+）。定义是「通过社交 feed **或类似的发现方式**再分发、放大用户内容，让它明显传播给很多用户」。世界地图就是让所有人发现别人公开作品的方式，以后还会加点赞；按保守理解应该勾选。勾「否」的风险是审核按 2.3.6（元数据不实）退回，或者上架后被要求改。
- **内容 › 粗俗语言或低俗幽默：偶尔**（9+）。街头贴纸、涂鸦里常有脏话和低俗玩笑（示例里就有「Mina Furz stinkt」），社区规则禁止色情、暴力、仇恨，但不禁止这些。
- **内容 › 成熟或暗示性主题、暴力、色情或裸露、医疗、赌博、恐怖等：无**：社区规则禁止，并由审核与举报处理。
- 应用内控制（家长控制、年龄验证）：无。消息与聊天：否（没有私信或评论）。广告：否。不受限制的网页访问：否。

→ 预计结果 **13+**（由「社交媒体」决定）。以后如果加评论或私信，要重答。

### 9.3 App 审核信息 · 备注（英文，原样粘贴）

```
GeoGhost is a personal field guide for street stickers, graffiti and murals. No account or sign-in is needed, and there are no in-app purchases.

Collecting (on-device): tap Capture, photograph or import a sticker, hold a finger on it to cut it out, then Save. The piece appears in Collection and on Map.

Online features (new in 1.1, optional):
- Map tab → "World" shows pieces other people chose to publish (try the Tokyo area). Tap a cluster to zoom in, tap a sticker to open it.
- Publish: open one of your pieces → "Publish to the world map". The preview shows exactly what becomes public: only the cutout, a location rounded to about 100 m, the day and a nickname. The first time, you choose a nickname and agree to the Community Rules (zero tolerance for objectionable content): https://passerbo.github.io/GeoGhost/community-rules/
- New publishers' first posts are reviewed by us before others can see them, so a post you publish during review will show "In review".
- Report: open someone's piece on the World map → ··· → Report. The post disappears for the reporter immediately; a post reported by three people is hidden from everyone until we review it again. Every report is reviewed within 24 hours.
- Block: ··· → Block hides all of that person's posts at once; unblock in Settings → Online.
- Settings → Online → "Delete my online data" removes everything the user put online.

Contact for moderation questions: the email in this App Review Information.
```

### 9.4 其他

- 商店描述是否提到世界地图：另起变更（prepare-ugc-release 不含商店文案）。
- 「What's New」1.1.0：发布时写 `scripts/release-notes/1.1.0.json`。

## 10. TestFlight 外部测试（Beta App Review）

> 2026-11-19。App Store Connect → TestFlight → 「测试信息」（Test Information）。外部群组的第一个构建要过 Beta App Review（通常 1 天内）。

**Beta 版 App 描述**（英文，原样粘贴）

```
GeoGhost is a field guide for the stickers, graffiti and murals you find on the street. Photograph a piece, cut it out on your iPhone, and it joins your collection and your map; the same design found again elsewhere is linked into a series.

This beta adds optional online features: publish pieces you choose to a shared world map, browse what others found, report or block, and delete everything you put online at any time. No account is needed.
```

- **反馈邮箱**：（你的邮箱）
- **营销网址**：`https://passerbo.github.io/GeoGhost/`
- **隐私政策网址**：`https://passerbo.github.io/GeoGhost/privacy/`

**Beta 版 App 审核信息**

- 需要登录：**否**
- 联系人：（你的姓名 / 电话 / 邮箱）
- 备注：与 §9.3 的 App 审核备注相同（原样粘贴）。

**测试内容（What to Test，每个构建都填；en / ja / zh-Hans）**

```
en:
New in this build:
- Map → World: browse pieces other people published. Tap a cluster to zoom in.
- Publish one of your pieces from its page. New publishers' first posts are checked before others see them ("In review").
- Report or block from a published piece's ··· menu.
- New here? On an empty Collection, try "Try a sample photo" to practise cutting out.
Please tell us where cutting out a sticker was hard, and anything that felt confusing. Settings → Send feedback, or a TestFlight screenshot.
```

```
ja:
このビルドの新機能:
- マップ → ワールド：ほかの人が公開した作品を見られます。まとまりをタップすると拡大します。
- 作品のページから公開できます。初めての方の最初の数件は、審査のあと公開されます（「審査中」）。
- 公開された作品の「···」メニューから報告・ブロックできます。
- 図鑑が空のときは「サンプル写真で試す」で切り抜きを練習できます。
切り抜きが難しかったところや、わかりにくかったところを教えてください（設定 → フィードバックを送信、または TestFlight のスクリーンショット）。
```

```
zh-Hans:
本版本新增：
- 地图 → 世界：浏览其他人公开的作品，点按聚合可以放大。
- 在作品页公开作品。新用户最初的几件会先审核，通过后其他人才能看到（「审核中」）。
- 在公开作品的「···」菜单里可以举报或屏蔽。
- 图鉴为空时，可以点「用示例照片试试」练习抠图。
请告诉我们哪里抠图困难、哪里让你困惑（设置 → 发送反馈，或 TestFlight 截图）。
```

## 11. 1.1.0 提交前的检查清单

按顺序做，前面的会影响后面：

1. ☐ **合并到 main 并推送**：社区规则页、支持页要上线，审核备注里的规则链接才打得开（现在是 404）。
2. ☐ **世界地图有内容**：审核备注让审核员看东京附近，那里必须有已公开的贴纸（explore-map T7 种子内容）。
3. ☐ **审核期间盯着审核后台**：审核员发布的贴纸会进「待审核」，尽快处理；他们也可能举报。
4. ☐ **App 隐私**按 §9.1 更新（发布脚本不会改，提交前必须手动改完）。
5. ☐ **年龄分级**按 §9.2 重答（用户生成内容、社交媒体 = 是；粗俗语言 = 偶尔；预计 13+）。
6. ☐ **审核备注**换成 §9.3。
7. ☐ **商店文案**：按 docs/07「1.1.0」一节替换描述与宣传文本；截图可沿用，建议之后补一张世界地图。
8. ☐ **「新功能」**：`scripts/release-notes/1.1.0.json` 已写好，`scripts/release.sh` 会填入。
9. ☐ **App Store Connect 里没有挂着的旧版本**：商店上是 1.0；如果 1.0.1 还在「准备提交 / 等待审核」，要先决定撤回或并入。
10. ☐ **最低支持版本保持 1.1.0**（审核后台 → 设置）。
