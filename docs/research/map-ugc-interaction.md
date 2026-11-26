# 以地图为基底的用户内容：别人怎么设计 · 调研

> 2026-11-26 · 调研（未改代码）· 为改进世界地图（[add-explore-map](../spec/changes/add-explore-map/proposal.md)）提供依据

结论先说：**地图做得好的产品，靠的不是数据多，而是三件事：每个图钉都经过挑选并且自己带信息；镜头是设计出来的；用户自己的足迹让地图永远不空。** 地图之外再配一个同步的列表。GeoGhost 的世界地图现在三件都没做到，而且打开时停在没有内容的地方。

> 这份笔记分两轮。第一轮（§2）主要看了同类的街头艺术产品和可用性研究，结论偏向「地图只是索引」。产品负责人指出这个结论下得太早：调研范围应当是所有以地图为主的用户内容产品，不能因为一个做得差的老产品就放弃优化地图。第二轮（§3）补看了地图本身做得最好的产品，§4 的建议以第二轮为准。

---

## 0. 怎么得出的、哪些没验证

- 搜了 14 组关键词，读了 17 个页面核实。
- 看的产品：Street Art Cities（最接近的同类）、FlashInvaders、Buffed、Graffiti Spot（街头艺术）；Snap Map、TapMap（社交）；iNaturalist、eBird（自然观察）；Geocaching（寻宝）；酒店和门店地图的可用性研究（Baymard、NN/g、MakeMyTrip）；Apple 的地图设计指南；Strava 热力图事件。
- **依据强弱差别很大**：可用性测试只有 Baymard、NN/g 和 MakeMyTrip 的 12 人测试；其余是产品自己的更新说明、帮助页和商店介绍，说明「他们做了什么」，不说明「效果如何」。
- **没读到**：eBird 的两篇说明（拒绝自动访问，只有搜索摘要）；iNaturalist 的隐私详解；一篇地图设计文章的付费部分；Zenly、Polarsteps、Beli 的设计分析；Pokémon GO 除审核规则外的地图设计。
- **所有来源都没讲**：地图上没有内容的地方该显示什么。这一条只能自己判断。

### 实际试用的补充（2026-11-27，产品负责人）

上面关于 Street Art Cities 的内容都来自它的更新说明和商店介绍，没有人实际用过。产品负责人试用后的评价：

- 地图本身不流畅，上面塞满重叠的红色数字点，没有给用户实际有用的信息。
- 它靠大量数据点把地图铺满，让点本身充当入口，没有任何引导；真正的交互都发生在地图以外。

由此得出两点，优先于下面从文档里读到的印象：

- **数据量大不等于地图好用。** 「铺满」这条路 GeoGhost 走不了（内容少），也不值得走。
- **地图上的每个标记都要自己带信息，地图要有引导。** 一个只有数字的点不告诉用户那里有什么。

## 1. 现状（2026-11-26 在模拟器里看到的）

- 打开世界地图，停在用户自己所在的街区，底部写「这里还没有公开作品」。
- 全世界只有 4 件公开作品，都在东京；缩小到日本全图才看到一个带数字 4 的图钉。
- 点图钉只是放大四分之一，要点好几次才能看到单件作品。
- 除了地图没有别的浏览方式。

## 2. 七个设计点，别人怎么做

### 2.1 打开时看到什么

| 产品 | 做法 | 来源 |
|---|---|---|
| Snap Map | 打开是用户自己的位置；热区一眼可见 | MakeUseOf，2019，可能过时 |
| 一个小型社交地图 App | 修过一个问题：登录后地图停在大洲尺度；改成定位后立刻到城市尺度 | GitHub 上的一条改动记录 |
| TapMap | 地图上面叠一摞可滑动的卡片，不注册也能看 | 创始人自述 |

NN/g 的测试里，用户喜欢一打开就看到地图，但用地图挑地点比用列表慢。没有来源讨论「用户所在的地方没有内容」的情况。

### 2.2 密集的地方怎么表示

- 随缩放级别换表示方式是通行做法：Snap 用热力颜色；iNaturalist 远看是方格、近看是单个标记；eBird 远看是按物种数上色的格子、近看是单个热点；Apple 的指南要求重叠的点合并，放大时逐步展开。
- **带数字的聚合图钉有风险**：NN/g 在门店地图的测试里发现它「让多数用户困惑」（2014 年）。MakeMyTrip 的测试里，聚合让人「点不中任何一个标记」，改法是调默认缩放、降低每一级的标记密度。
- GeoGhost 的聚合图钉是「一张代表作品 + 数字」，比纯数字好懂，但点击行为有问题，见下一条。

### 2.3 点一下之后发生什么

- **Snap Map：点热区，直接开始播放那里的内容**，左右点切换。不需要先放大到单个内容。
- MakeMyTrip：点标记才出现卡片；原来按热门度排序的卡片轮播和地图位置对不上（相邻的卡片在地图上相距几公里）。
- Apple 的指南：显示地点卡片时，地图上那个位置要保持可见。
- GeoGhost 现在点聚合只放大。自己的地图（「我的」）点聚合是弹出列表，世界地图反而没有。

### 2.4 地图之外的第二条路

- **Baymard（酒店搜索，大规模可用性测试）**：只给列表的网站上，65% 的用户从没用过地图；地图和列表并排最好；两者不同步是最大的坑（Expedia 上 75% 的用户缩放地图后回到列表，看到的还是没筛选的结果）。
- **NN/g（找门店）**：手机上应当列表优先、地图可切换。和 Baymard 看似矛盾，其实任务不同：找最近的门店只需要距离；酒店和「钉在地点上的照片」需要知道具体在哪。后半句是推断。
- **Street Art Cities**：地图 + 列表 + 路线，2026-07 加了一个叫「Everything」的实时动态流。
- **FlashInvaders**：有一个「最新验证的发现」实时页面。
- **Geocaching**：地图旁边有按距离排序的列表，指到哪一项，地图上对应的点高亮。

### 2.5 把「我」记在地图上

- Geocaching：找到过的点变成笑脸，地图和列表里一致。
- Street Art Cities：标记「看过」、收藏、徽章、连续天数；每面墙有时间线，显示这里以前有过什么作品；作品页有「看过」的人数。
- FlashInvaders：每拍到一个得分，每个城市有总分，有排行榜。

### 2.6 位置隐私

- iNaturalist：敏感物种的位置在一个 0.2° × 0.2° 的方格里随机取点（赤道附近约 500 平方公里）；观察者自己始终能看到真实位置。
- Strava：2018 年热力图暴露了军事基地之后，改成活动太少的路段不显示。
- Snap：限制来自学校、医院等地点的用户内容。
- Buffed：作者可以把自己的墙模糊成一片区域，而不是精确的点。Graffiti Spot：存照片时去掉位置信息。
- GeoGhost 公开位置只精确到约 100 m，和这些做法方向一致。没有找到「公开位置导致街头作品被清除」的报道，这个风险只能算未知。

### 2.7 冷启动和内容质量

- TapMap：发现功能必须在用户还没有好友时就有用；只在一个地方（普吉岛）上线。
- Andrew Chen《冷启动问题》：先在一个地方做到密度。Street Art Cities 有 15 个官方合作城市，并且要求贡献者「和自己负责的城市有很深的联系」。
- Street Art Cities 的一条一星评价抱怨：搜城市、按位置看地图要付费。GeoGhost 已经定了浏览免费，保持。

## 3. 第二轮：地图本身做得好的产品（2026-11-27）

五个方向分头查：社交地图（Snap Map、Zenly、Bump）、游戏和收集（Pokémon GO、Ingress、Geocaching、Fog of World）、图钉设计（Airbnb、Google、Apple）、众包数据（Waze、Strava、Komoot、AllTrails）、地图平台和地图类 SaaS 的指南（Mapbox、Google、Apple、Proxi、Mapme）。

依据的强弱：**有实验数据的只有 Airbnb 的论文**（每组 3400 万用户）；Zenly 有前设计负责人的两篇长文；其余是帮助页、产品新闻和观察者的描述。各页面是通过摘要工具读的，引用具体数字前要回原文核对。

### 3.1 每个图钉都经过挑选，并且自己带信息

- **Airbnb（论文，有实验）**：
  - 只给「值得看」的房源放图钉，图钉减少约 39%，订单反而增加 1.9%。
  - 随机去掉图钉（18 个里留 14 个）订单下降 1.5%——起作用的是挑选，不是数量少。
  - 图钉分两级：最好的用带价格的大图钉，其余用不带信息的小圆点；小圆点的点击只有大图钉的八分之一左右，但让所有内容都「在场」。
  - 95% 点过地图的用户点的图钉不超过 12 个。
- **Komoot**：缩小时只显示最受欢迎的亮点，放大才露出其余的。
- **照片地图的通行做法**（Apple 照片、Meta 的一项专利）：一张代表照片加角上的数量，而不是纯数字圆圈；代表照片按最新、最受欢迎来选；格子的大小保证缩略图互不重叠；四张以下的聚合直接展开成缩略图列表。
- **Apple 和 Google 的平台能力**：都支持「重叠时按优先级隐藏」，不必合并成数字。
- **反面**：NN/g 测出纯数字聚合让多数用户困惑；Street Art Cities 的实际体验是一屏重叠的红色数字点。

### 3.2 镜头是设计出来的

- **Airbnb（论文）**：注意力在地图中心最高，向四周衰减。它专门挑地图的中心点，让最好的内容落在中间（新用户订单 +0.39%，用户挪动地图的次数 −1.5%）；手机网页上曾经出过卡片盖住下方图钉的问题。
- **Bump**：打开就是「一眼能看到朋友在哪」的缩放级别。
- **Zenly**：团队承认没有朋友时的空地图是很差的第一印象。
- 小项目的常见做法：把内容框进画面并留边，同时给缩放设上限，单个点用固定缩放。

### 3.3 交互发生在地图上

- **Snap Map**：点热区，直接播放那里的内容。
- **Bump**：点一个地点，在地图上展开营业时间、排行和去过的朋友。
- **Airbnb**：点小圆点出一张小卡片。
- **Apple 的指南**：显示地点卡片时，那个位置要保持可见。
- 手机上更推荐「搜索这片区域」按钮，而不是一挪地图就自动刷新——图钉在用户眼前变来变去，会让人记不住看过什么。

### 3.4 用户自己的足迹让地图永远不空

这是第一轮完全没看到的一点，也是对内容少的产品最有用的一点。

- **Zenly**：走过的地方迷雾散开，常去的地方自动出现，「不需要用户做任何事」。
- **Snap 足迹**：显示去过的国家和一个区域走过的比例，用用户已有的照片预先填好。
- **Bump**：刮刮地图，显示还没探索过的地方。
- **Pokémon GO**：没去过的补给站有一圈白环，去过之后永久消失。**Geocaching**：找到过的点变成笑脸。
- **别人的存在是痕迹，不是实时位置**：Niantic 的负责人说，其他玩家留下的痕迹让一个地方「感觉是活的」。

### 3.5 内容会过时，重复是证据

- **Waze**：路过时弹出「还在 / 不在了」，一点完成；每条内容有随时间下降、被确认后回升的可信度。
- **Komoot**：路过的亮点事后请用户评价；重复的条目合并成一条，照片和说明汇在一起。
- **Strava**：热度按局部归一化，每一屏都有对比；用绝对数值，内容少的地方看起来就是空的。它「人数不够就不显示」的门槛不适合内容很少的阶段。

### 3.6 空白的地方

- **Niantic** 在内容少的地区自动生成了一批通用的点，玩家反感。
- 更好的做法是换一句话：从「来找」换成「成为第一个在这里添加的人」。
- 平台和可用性研究都没有关于空白地图的指南。

### 3.7 手感和性能

- **Zenly** 想让地图「更像游戏或玩具」；**Bump** 用弹性动画。一个小团队做不了自己的地图引擎，但可以把力气花在少数几处有玩具感的细节上。
- **iOS 上的实际限制**（开发者报告，没有严格的基准测试）：SwiftUI 的地图上放几千个标记很卡；带网络图片的图钉是主要瓶颈；有人说 50 个自定义标记就会影响帧率。按「缩略图互不重叠」来算，手机一屏本来也只放得下 15–30 个。
- 缩放时避免跳变：标记按它显示的那张照片来识别，而不是按每一级的聚合编号。

### 3.8 地图类 SaaS 的「标准配置」

Proxi、Mapme、Padlet、Felt 提供的都差不多：地图加同步的侧边列表、分类筛选、低门槛的提交表单、发布前的审核队列。GeoGhost 已经有提交和审核，缺的是列表和筛选。

## 4. 对 GeoGhost 世界地图的建议

以第二轮为准。**这一版做**：

1. **镜头**：打开时框住离用户最近的一片内容，最好的落在中间；设缩放上限；不停在空白街区。（3.2）
2. **图钉**：保持缩略图图钉；一屏的缩略图有上限（约 20 个，互不重叠），其余用小圆点；挑选按最新和点赞。聚合是「一张代表作品加数量」，不出现纯数字的点。（3.1、3.7）
3. **在地图上看内容**：点图钉，在地图上出一张小卡片，地图上那个位置保持可见；点聚合，直接出这一格的作品，可以滑着看。（3.3）
4. **同步的列表**：「最新发现」，点一件，地图移过去；地图挪动后列表跟着变。（第一轮 2.4、3.8）
5. **空白的地方**：一句「成为第一个在这里添加的人」，加一个跳到最近作品的按钮。（3.6）
6. **把自己的作品也放在世界地图上**，用不同的样子区分（3.4）：新用户收集的第一张贴纸就能出现在世界地图上，地图不会是空的。这会改变 2026-11-12 定下的「我的 / 世界」切换，需要产品负责人决定。

**以后做**（阶段 2 的候选）：

- 别人的作品上的「我也见过」，以及把同一款贴纸合并成一个条目——跨用户系列（3.5 的 Komoot，第一轮的 Street Art Cities）。
- 「还在吗」的一键确认，让被撕掉的贴纸逐渐淡出（3.5 的 Waze）。
- 足迹或迷雾、按城市的进度（3.4）。
- 种子内容集中在一个街区（第一轮 2.7）。

## 来源

- Street Art Cities：[2026-03 更新](https://streetartcities.substack.com/p/the-streets-keep-moving-and-so-does) · [2026-07 更新](https://streetartcities.substack.com/p/street-art-cities-update-super-hunters) · [App Store](https://apps.apple.com/app/street-art-cities/id1161541872)
- [FlashInvaders 帮助页](https://www.space-invaders.com/flashinvaders/web_help_v3) · [Graffiti Spot](https://graffitispot.app/about) · [Buffed](https://apps.apple.com/us/app/buffed-graffiti-street-art/id6815035788) · [街头艺术影像分享的历史（Ross）](https://jeffreyianross.medium.com/tracing-the-history-of-documenting-and-sharing-images-of-graffiti-street-art-0f6070a3055e)
- Snap Map：[怎么用（MakeUseOf）](https://www.makeuseof.com/tag/how-to-use-snapchat-map) · [内容怎么排序和审核（Social Media Today）](https://www.socialmediatoday.com/news/snapchat-map-algorithm-notes/741588/)
- [TapMap 创始人自述](https://dev.to/yurii_tapmap/building-tapmap-why-we-put-discovery-and-friends-on-the-same-map-4jp1) · [地图冷启动停在世界尺度的修复](https://github.com/ValentinGanchevA1/general/pull/394) · [Andrew Chen《冷启动问题》节选](https://andrewchen.com/wp-content/uploads/2022/01/ColdStartProb_9780062969743_AS0928_cc20_Final.pdf)
- iNaturalist：[地图符号](https://help.inaturalist.org/en/support/solutions/articles/151000170218-what-do-the-map-symbols-mean-) · [敏感物种的位置保护](https://help.inaturalist.org/en/support/solutions/articles/151000233080-how-does-inaturalist-protect-the-locations-of-sensitive-species-)
- eBird（只有搜索摘要）：[热点地图](https://ebird.org/region/CA/post/introducing-the-ebird-hotspot-explorer)
- Geocaching：[搜索和地图筛选](https://www.geocaching.com/blog/?p=88944) · [App 的新导航](https://www.geocaching.com/blog/2018/11/guide-to-the-geocaching-apps-new-navigation/)
- 可用性研究：[Baymard：列表、地图和并排视图](https://baymard.com/blog/accommodations-split-view) · [NN/g：手机上的地图和地点](https://www.nngroup.com/articles/mobile-maps-locations/) · [MakeMyTrip 地图改版](https://medium.com/swlh/map-design-for-hotel-bookings-ae3e97a44e36)
- [Apple 人机界面指南：地图](https://developer.apple.com/design/human-interface-guidelines/maps)
- Strava 热力图：[事件](https://www.bikeradar.com/news/article/stravas-heatmap-reveals-military-bases-and-more-51637/) · [之后的修改](https://cyclingweekly.com/news/latest-news/strava-updates-heatmap-revealed-locations-secret-military-bases-372967)
- [Pokémon GO 的地点提名](https://niantic.helpshift.com/hc/en/6-pokemon-go/faq/41-submitting-a-pokestop-nomination/) · [对其审核标准的批评](https://walklistencreate.org/2020/03/25/niantic-wayfarer-and-pokemon-go-cultural-geographies-of-wayspot-reviewing/)

### 第二轮的来源

- Airbnb：[地图搜索排序（博客）](https://airbnb.tech/ai-ml/improving-search-ranking-for-maps/) · [论文](https://arxiv.org/html/2407.00091v1) · [地图设计师的作品集](https://www.adamshutsa.com/map-platform/)
- Zenly：[设计回顾（一）](https://medium.com/@julienmartin_/designing-zenly-part-i-ec7dc0a1e3ad) · [设计回顾（二）](https://medium.com/@julienmartin_/designing-zenly-part-ii-3e525eb10ef0) · [自研地图引擎（TechCrunch）](https://techcrunch.com/2022/05/18/social-maps-app-zenly-rolls-out-its-own-maps/amp/) · [迷雾（Mapbox）](https://medium.com/mapbox/clear-the-fog-with-zenly-fc7778b06c33)
- Snap Map：[上线（TechCrunch）](https://techcrunch.com/2017/06/21/snap-map/amp/) · [回忆和探索图层](https://techcrunch.com/2021/11/17/snapchat-launches-memories-and-explore-layers-on-snap-map/amp/) · [足迹](https://techcrunch.com/2024/09/30/snapchats-new-footsteps-feature-tracks-your-location-history) · [月活 4 亿](https://newsroom.snap.com/2025-snap-map-mau)
- Bump：[怎么用](https://help.bumpmaps.com/en/articles/11420926-how-bump-works) · [团队访谈](https://appstacks.club/bump)
- Pokémon GO：[补给站的各种状态（Bulbapedia）](https://bulbapedia.bulbagarden.net/wiki/PokéStop) · [附近栏](https://pokemongo.com/news/nearby-nov2016) · [内容少的地区自动生成的点](https://community.wayfarer.scopely.com/t/testing-new-wayspots-in-pokemon-go/109242) · [Hanke 访谈](https://gamesbeat.com/?p=113651)
- [Ingress 情报地图的分级显示](https://fevgames.net/ingress/ingress-guide/concepts/intel-map/) · [Geocaching 重做导航的原因](https://www.geocaching.com/blog/?p=61181) · [Fog of World](https://fogofworld.app/en/)
- Waze：[还在 / 不在了](https://support.google.com/waze/answer/12237550?hl=en) · [可信度评分](https://support.google.com/waze/partners/answer/10618551)
- [Komoot 的亮点](https://support.komoot.com/hc/articles/10364710659994) · [Strava 热力图的做法](https://medium.com/strava-engineering/the-global-heatmap-now-6x-hotter-23fc01d301de) · [Strava 热力图的显示门槛](https://support.strava.com/hc/en-us/articles/216918877)
- 平台指南：[Apple WWDC17 MapKit（文字稿）](https://nonstrict.eu/wwdcindex/wwdc2017/237/) · [Apple WWDC23 MapKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10043/) · [Google 的标记碰撞规则](https://developers.google.com/maps/documentation/ios-sdk/advanced-markers/collision-behavior) · [Mapbox 聚合算法](https://medium.com/mapbox/clustering-millions-of-points-on-a-map-with-supercluster-272046ec5c97)
- 照片地图：[Apple 照片的地点地图](https://support.apple.com/guide/photos/find-photos-and-videos-by-location-pht4c00b8ddc/mac) · [Meta 的照片地图专利](https://patents.google.com/patent/US9047847)
- iOS 性能（开发者报告）：[图片图钉](https://developer.apple.com/forums/thread/739299) · [SwiftUI 地图](https://developer.apple.com/forums/thread/729641) · [ClusterMap](https://github.com/vospennikov/ClusterMap)
- [「搜索这片区域」](https://mapuipatterns.com/search-this-area/) · 地图类 SaaS：[Proxi](https://proxi.co/crowdsource-maps) · [Mapme](https://mapme.com/solutions/crowdsourcing-map/)
