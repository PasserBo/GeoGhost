# Tasks: add-series-share-card

## Now
2026-11-23：agent 的任务都做完了，包括定位小图。系列页有分享入口，两种卡可以左右滑，封面、原图、命名都能用，同城的系列在地图一角有国家轮廓，导出是 1080×1350 的 PNG。
还差 me 的两件：T11 真机走查；T12 读许可协议的地图附件。
另外两件不属于这次改动、但跑快照时碰到的事：`series_list.empty`、`collection.empty`、`feedback.empty` 的基准图与现在的界面不一致（看板 10、12 里写了要重录）；只跑 `series_detail.` 这一组快照时测试进程会在结束时崩溃（地图图钉在数据销毁后还在刷新），和其他状态一起跑不会。

## M1 · 通用分享页
- [x] T1 `ShareCardOption`、`ShareCardDeck`、`ShareCardRenderer`：左右滑动预览、页码和名字、分享按钮、导出 PNG、失败提示 — owner: agent · verify: 构建通过；模拟器里滑动和导出 · done 2026-11-23
  - evidence: 构建通过；iOS 26.3 模拟器里左右滑切换两种系列卡，分享后临时目录里生成 GeoGhost-card-series-encounters.png（1080×1350）
- [x] T2 单件作品的分享页改用 Deck，四种样式各是一个 Option，Pro 上锁和标记开关照旧 — owner: agent · after: T1 · verify: 现有 share_card.* 基准图不变；模拟器里单件分享照常 · done 2026-11-23
  - evidence: scripts/ui-snapshots.sh verify share_card. 通过（四种样式的基准图没变）。Pro 样式现在不显示，上锁样式的滑动没有在界面上走过

## M2 · 系列卡
- [x] T3 `SeriesStats`：对齐后的坐标、最远距离、时间跨度、跨城市、距离写法 — owner: agent · verify: 单元测试 SeriesStatsTests · done 2026-11-23
  - evidence: SeriesStatsTests 7 项全过
- [x] T4 `RouteMapSnapshotter`：静态地图和各点位置，8 秒超时，失败返回空 — owner: agent · verify: 模拟器里联网能出图；断网时卡片没有地图 · done 2026-11-23
  - evidence: 模拟器联网出图：跨城市（东京—大阪）和同城（高円寺一带）各一张。断网和超时没有实测，只有代码路径
- [x] T5 两种系列卡的版面、路线地图层、`SeriesShareCards` 的选项和默认规则 — owner: agent · after: T1, T3 · verify: 界面快照 series_share_card.*；单元测试默认规则 · done 2026-11-23
  - evidence: 快照 series_share_card.distance / encounters / no_location 已录并通过；默认规则在 SeriesStatsTests 里
- [x] T6 `SeriesShareSheet`：编号、封面选择、原图开关、命名；系列页加入口（两次相遇以上） — owner: agent · after: T4, T5 · verify: 模拟器里走一遍 · done 2026-11-23
  - evidence: 模拟器里走过：入口、编号、原图开关、没有名字时不显示名字行。换封面和在分享页改名没有逐项点过
- [x] T7 新文字的简体中文和日语翻译 — owner: agent · after: T5, T6 · verify: 三种语言的快照里文字都放得下 · done 2026-11-23
  - evidence: 三种语言的 series_share_card.distance 快照里文字都放得下

## M3 · 定位小图
- [x] T8 同意下载 Natural Earth 国家轮廓数据（公共领域，原文件实际 3.1 MB，来自 GitHub 的 nvkelso/natural-earth-vector） — owner: me · verify: 回复同意 · done 2026-11-23
  - evidence: me 在对话里回复「可以，下载」
- [x] T9 精简轮廓数据并打包，`CountryOutlines` 按国家代码读取，地图上画定位小图 — owner: agent · after: T8 · verify: 快照 series_share_card.same_city 里有日本轮廓和定位点；App 体积增加不超过 300 KB · done 2026-11-23
  - evidence: scripts/build-country-outlines.py 由 ne_50m_admin_0_countries.geojson（3.1 MB）生成 GeoGhost/Resources/CountryOutlines.json：237 个国家和地区，打包后 208 KB。快照 series_share_card.same_city 里有日本轮廓和定位点；iOS 26.3 模拟器里同城系列导出的图上也有

## M4 · 收尾
- [x] T10 `ui/screen.yaml`、`translations.yaml`、`ScreenCatalog` 加系列卡的状态并录基准图 — owner: agent · after: T5 · verify: scripts/ui-snapshots.sh verify 通过 · done 2026-11-23
  - evidence: verify series_share_card. 和 series_detail. 的图都一致（series_detail 的工具栏多了分享按钮，基准图已重录）
- [ ] T11 真机走查：真实系列生成两种卡，发到相册看清晰度；断网再试一次 — owner: me · after: T6 · verify: me 确认
- [ ] T12 读 Apple 开发者许可协议里关于地图的附件，确认导出图片的标识做法（现状：快照自带 Apple 的 Maps 标志，卡片原样保留、不遮挡，没有另加文字） — owner: me · verify: me 确认，或告诉 agent 要改什么

## 附带
- [x] T13 调试用的演示数据：启动参数 `-seedDemoSeries YES` 生成两个画出来的系列（跨城市一个、同城一个），只在 Debug 构建里有 — owner: agent · verify: 模拟器 · done 2026-11-23
  - evidence: iOS 26.3 模拟器里生成了 Orange cat 和一个未命名系列
