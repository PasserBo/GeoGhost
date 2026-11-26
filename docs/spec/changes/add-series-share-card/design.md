# Design: add-series-share-card

## 1. 结构：选择器不认识卡片，卡片不认识选择器

```
Features/Share/
├── ShareCardOption.swift     一种可选的卡：id、名字、是否上锁、怎么画（一个返回视图的闭包）
├── ShareCardDeck.swift       通用分享页主体：左右滑动预览、页码、分享按钮、导出成图片
├── ShareCardRenderer.swift   把任意卡片视图画成 1080×1350 的 PNG
├── ShareCardSheet.swift      单件作品的分享页：准备内容 → 交给 Deck（四种样式各是一个 Option）
├── ShareCardView.swift       单件作品的四种样式（没改）
└── Series/
    ├── SeriesShareSheet.swift    系列的分享页：准备内容、封面 / 原图 / 名字三个控件 → 交给 Deck
    ├── SeriesCardContent.swift   系列卡要显示的全部数据（值类型，不碰数据库）
    ├── SeriesShareCard.swift     两种系列卡（距离、次数）和它们共用的版面
    ├── SeriesRouteMapView.swift  地图底图上叠路线、相遇点、地名、定位小图
    └── SeriesShareCards.swift    由内容得出有哪些 Option、默认哪一个
Domain/SeriesStats.swift          纯计算：最远距离、时间跨度、是否跨城市、距离的写法
Services/Maps/RouteMapSnapshotter.swift   取一张静态地图，并给出每个点在图上的位置
Services/Maps/CountryOutlines.swift       按国家代码取轮廓（Resources/CountryOutlines.json）
```

加一种新卡 = 写一个视图 + 在对应的 `…ShareCards` 里多返回一个 `ShareCardOption`。Deck、导出、分享页都不用动。加一种新的分享对象（例如地区合集）= 一个新的 Sheet 准备内容和控件，然后交给同一个 Deck。

## 2. 数据流

1. Sheet 从模型里读出需要的值，做成 `SeriesCardContent`（值类型）。之后画卡不再碰 SwiftData，所以导出时的离屏渲染是安全的。
2. 地图是异步取的：先显示不带地图的卡，取到后内容更新、卡片重画。取不到（没有网络、8 秒超时）就保持没有地图。
3. 封面图在选择变化时重新读取；原图读不到时退回抠图。

## 3. 位置和距离

- 进入卡片前，所有坐标先用 `LocationBlur.snap` 对齐到约 100 m，重复的点合并。距离、地图、定位小图都用对齐后的坐标。
- 最远距离 = 所有点对之间的最大大圆距离。一个系列的相遇次数很少，两两比较足够。
- 跨城市的界线 `SeriesStats.crossCityMeters = 30 km`，只决定默认卡。不用地名判断，因为东京 23 区各算一个 locality。
- 距离卡的门槛 100 m：对齐后小于这个值的距离没有意义。
- 距离的写法：1 km 以上写 km（100 以下留一位小数），以下写 m（取整到 50）；英里同理留一位小数。数字用当前语言的格式，单位写法固定。

## 4. 地图

- `MKMapSnapshotter`，浅色、低饱和（muted）、不显示兴趣点。范围 = 相遇点的外接范围加留边，纬度跨度不小于 0.015°（约 1.6 km）。
- 快照自带 Apple 的「Maps」标志，在左下角（2026-11-23 在 iOS 26.3 模拟器上确认）。它就是地图的署名：原样保留，自己画的定位小图放在左上角，不另外加来源文字。
- 外接范围的留边是纬度 ×2.0、经度 ×1.9，让最外侧的相遇点落在中间一半左右，避开左下角的标志。
- 路线、相遇点、地名用 SwiftUI 画在底图之上，位置来自快照给出的换算，所以测试里可以用一张纯色底图加算好的位置，不依赖网络。
- 定位小图：最远两点相距小于 250 km、所有点同属一个国家、有这个国家的轮廓、并且相遇点落在轮廓的范围内时显示。
- 轮廓数据 `CountryOutlines.json` 由 `scripts/build-country-outlines.py` 从 Natural Earth 50m 国家数据（公共领域）生成：每个国家只留主体和附近较大的部分（面积不小于主体的 3%、中心相距不超过 25°），简化到约 10 km。所以海外领地和远离本土的部分（阿拉斯加、法属圭亚那）不在轮廓里，在那里的相遇点不显示小图。

## 5. 取舍

- **Option 用闭包返回 `AnyView`，不用协议加泛型**：卡片种类是运行时决定的列表（有没有距离卡、Pro 样式显不显示），类型擦除在这里是需要的；每张卡一秒内只画几次，没有性能问题。
- **单件作品的分享页也迁到 Deck**：否则「通用」只是说说。Pro 样式现在不显示，所以用户今天看到的界面没有变化；Pro 打开后，样式从胶囊按钮变成左右滑动，上锁的样式滑到时分享按钮变成解锁。
- **没有网络时不画示意路线**：规格写的是不带地图；示意图以后想加，是一种新的地图底图，不改卡片。

## 6. 版面随贴纸形状调整（2026-11-26）

- 形状只看抠图的宽高比；原图是填满格子的，不参与。
- 宽高比小于 0.7：左图右文（`Arrangement.sideBySide`）。左栏宽度 = 可用高度 × 宽高比，限制在 56–150 pt。
- 宽高比大于 1：仍是上图下文，但地图高度 = 112 + 贴纸省下的高度，按 8 pt 一档，最高 176。地图是按这个尺寸请求的，所以 `RouteMapImage` 带着自己的尺寸，卡片按它显示；封面换成另一种形状时分享页重新请求地图，请求不到就保留旧的。
- 这些数值都在 `SeriesShareCard` 顶部，`SeriesShareCardLayoutTests` 覆盖分档规则。
