# 分享内容的设计原则 · 调研

> 2026-11-23 · 调研（未改代码）· 为 [add-series-share-card](../spec/changes/add-series-share-card/proposal.md) 的开放问题提供依据

结论先说：**公开资料里，带数据的「分享卡设计原则」很少**。能找到的一手材料只有几条（Wordle 作者的访谈、Spotify 工程师的介绍、Duolingo 官方博客、Andrew Chen 的病毒循环文章），其余大多是营销博客对成功案例的事后解读。下面每条原则都标了依据的强弱。可以放心用的是方向，不是具体数字。

---

## 0. 怎么得出的、哪些没验证

- 搜了 12 组关键词，读了 4 篇原文核实（Duolingo、Andrew Chen、Spotify 工程博客、两篇 Indie Hackers 的 Reddit 经验帖）。
- **没找到**：Strava 自己讲分享图设计的文章；带水印和不带水印的对比数据；图鉴 / 收集类 App（Letterboxd、Untappd、Pokémon GO、iNaturalist）关于分享卡的案例。
- **不可信、没有采用**：一个第三方网站称 Duolingo 的定制分享卡让自发分享增加 5–10 倍，没有给出处，Duolingo 官方博客里没有任何数字。
- Reddit 的两篇经验帖是创始人自述，其中一篇结尾在推销作者自己的工具。

## 1. 八条原则

| # | 原则 | 依据 | 强弱 |
|---|---|---|---|
| 1 | **主角是分享的人，不是品牌。** 人们分享的东西是在说明「我是谁」；卡片展示的是「我的发现」，品牌只是落款。 | Jonah Berger 的「社交货币」；多篇对 Spotify Wrapped 的分析 | 理论成熟，对 Wrapped 的说法是解读 |
| 2 | **没用过产品的人也要两秒看懂，并且想问一句。** Wordle 的方格不透露答案，却把一局的过程讲完了，本身就是预告片。 | Wordle 作者 Josh Wardle 的访谈 | 一手 |
| 3 | **分享的形式跟着用户已经在做的事走。** Wordle 的方格是玩家自己先手打出来的，作者后来才做成按钮。Strava 用户原本在截图，Strava 于是做了透明的数据贴纸，让人叠在自己的照片上；Garmin 随后跟进，并提供 1:1、4:5、9:16 三种比例。 | Wardle 访谈；Strava 与 Garmin 的产品新闻 | 事实可靠，「为什么」是推断 |
| 4 | **一步完成，不离开 App。** | Duolingo 官方博客（连胜里程碑的分享卡：方图、角色、一句话）；Branch 的分享指南 | 官方说法，无数据 |
| 5 | **品牌标识要有，但要克制。** 图片要一眼认得出来自哪里，文字不要多。水印太大可能反过来拖慢传播；发布平台也可能限制带水印或回链的内容。 | Facebook 小游戏的分享图指南；Andrew Chen；一篇水印的个人文章 | 弱，没有对比数据 |
| 6 | **固定版面要扛得住各种数据。** Spotify 的分享卡要在固定空间里放下 30 种语言和长短不一的数据，设计和本地化从第一天就一起做。 | Spotify 工程师 Jordan Loeser 的介绍 | 一手 |
| 7 | **循环要算账，新鲜感会衰减。** Andrew Chen 举的例子：看到的人里 50% 看完、10% 点进去、20% 自己做一张、50% 再分享，一次分享要有 200 人以上看到才能自我增长。没有留存的爆发不持久。 | Andrew Chen《Braindump on viral loops》（2025-11） | 一手，数字是示意 |
| 8 | **Reddit 上不发链接；有人问再说；说明自己是开发者。** 直接发链接的结果是没人理或被删；有人问「用的什么工具」时再回答效果好。 | 两篇 Indie Hackers 自述 | 个例 |

## 2. 对 GeoGhost 意味着什么

- **不要指望系列卡自己形成病毒循环。** 按第 7 条的算法，Reddit 上的图片连链接都没有，「点进去」这一步比示例里的 10% 还低得多。系列卡在这个阶段的作用是让人记住名字、让人来问，而不是自动带来下载。衡量方式用提案里已经写的：评论里有多少人问「这是什么 App」。
- **卡片要讲的只有一句话**：「同一张贴纸，我在相隔 398 公里的两个地方都遇到了。」所有元素都为这句话服务（第 2 条）。
- **现有的小印章符合第 5 条**，保持现状是对的。
- **系列名字、地名长度、2 次和 20 次相遇、三种语言**都要在固定版面里放得下（第 6 条）。项目已有界面快照测试，系列卡应当加进去。
- **Strava 的教训和大图的选择直接相关**（第 3 条）：用户想把数据叠在自己拍的照片上，而不是只要一张 App 生成的图。

## 3. 对四个开放问题的建议

1. **最显眼的数字**：自动选最亮眼的（跨城市时放距离，同城时放次数）。理由是第 2 条：一张卡只讲一句话，哪个数字最让人想问就放哪个。
2. **范围说明**：第一版不写。地图加定位小图已经回答了「在哪里」；少一行文字，也少一处在三种语言下放不下的风险（第 6 条）。
3. **大图**：默认用抠图，提供一个开关换成原图。抠图保证图鉴的样子和版面稳定；原图对应第 3 条里 Strava 的做法，也保留街头的样子。分享的人多一个开关，不碰也能发。
4. **地图标识**：还没查，动手前由 agent 查清。

## 来源

- [Wordle 作者谈走红过程（Game Developer）](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success) · [彩色方格的由来（The Spinoff）](https://thespinoff.co.nz/media/13-01-2022/those-coloured-boxes-on-twitter-are-new-zealands-fault)
- [Spotify 工程师 Jordan Loeser 谈分享卡](https://engineering.atspotify.com/2022/3/jordan-loeser-web-engineer) · [Rive：Wrapped 2025 的模块化做法](https://rive.app/blog/spotify-used-rive-for-spotify-wrapped-2025)
- [Duolingo：连胜里程碑的设计](https://blog.duolingo.com/streak-milestone-design-animation)
- [Andrew Chen：Braindump on viral loops](https://andrewchen.substack.com/p/braindump-on-viral-loops)
- [Jonah Berger 谈人们为什么分享（Wharton）](https://knowledge.wharton.upenn.edu/article/contagious-jonah-berger-on-why-things-catch-on/)
- [Strava 的数据贴纸（BikeRadar）](https://www.bikeradar.com/news/strava-sticker-stats-spring-2025-updates) · [Garmin 的透明叠加图（T3）](https://www.t3.com/active/fitness-trackers/garmin-connect-app-transparent-overlay-0426)
- [Facebook 小游戏分享图指南](https://developers.facebook.com/documentation/games/acquire/sharing) · [水印与传播（Medium，个人文章）](https://medium.com/creators-of-vixt/watermarks-on-content-for-traction-861aabc4eaa1) · [Branch：分享链接](https://www.branch.io/resources/blog/how-mobile-apps-go-viral-user-generated-sharing-links/)
- Reddit 经验（自述）：[发了三个月链接之后](https://www.indiehackers.com/post/i-spent-3-months-posting-links-on-reddit-before-i-learned-the-platform-doesnt-work-that-way-f86690b224) · [两个月的 Reddit 推广](https://www.indiehackers.com/post/spent-2-months-marketing-on-reddit-went-viral-got-removed-heres-what-works-and-what-doesn-t-5f72c507db)
