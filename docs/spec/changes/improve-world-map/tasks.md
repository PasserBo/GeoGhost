# Tasks: improve-world-map

## Now
2026-11-27：五项都做完了，已合并到 main，并以 1.2.0 (119) 上传到 TestFlight。模拟器里用线上的 9 件作品走过：打开停在东京、缩略图标记和数量、点标记看里面的作品、放大到这里、滑动卡片地图跟着移动。空白区域的面板、邀请和指向提示只看了快照，没有在模拟器里走到。
统计事件没有接（见 design §6），需要 me 决定要不要另开一个变更。
还差 me：T11 真机走查（装 1.2.0 (119)）。

## M1 · 数据和规则
- [x] T1 `WorldFeed`：启动时后台加载、存盘、失败时保留上次的结果、举报和屏蔽后立刻移除 — owner: agent · verify: 单元测试 WorldFeedTests · done 2026-11-27
  - evidence: 4 项通过
- [x] T2 `WorldPinLayout`：并进同一处、缩略图上限、小圆点、画面外的不算 — owner: agent · verify: 单元测试 WorldPinLayoutTests · done 2026-11-27
  - evidence: 6 项通过
- [x] T3 `WorldCamera`：打开时框哪里、镜头移动的三档 — owner: agent · verify: 单元测试 WorldCameraTests · done 2026-11-27
  - evidence: 4 项通过
- [x] T4 `OwnAreaPrompts`：指向提示和邀请的条件、关闭记录 — owner: agent · verify: 单元测试 OwnAreaPromptsTests · done 2026-11-27
  - evidence: 6 项通过

## M2 · 界面
- [x] T5 `WorldMapView` 和卡片条：打开的镜头、标记、点标记看作品、最新发现、只看这片区域、放大到这里、与地图同步 — owner: agent · after: T1–T3 · verify: 模拟器 · done 2026-11-27
  - evidence: iOS 26.3 模拟器、线上后端：打开停在东京的 9 件；点写着 4 的标记出现「4 pieces here」；「Zoom in here」放大；滑到第二张卡片地图移到千代田区那件。「只看这片区域」和举报后消失没有点过
- [x] T6 空白区域的面板、邀请、选一件公开、指向提示 — owner: agent · after: T4, T5 · verify: 快照 world_empty_area.* / world_top_notice.* · done 2026-11-27
  - evidence: 快照已录并通过；三种语言的邀请和指向提示文字都放得下。没有在模拟器里走到这些状态
- [x] T7 新文字的简体中文和日语翻译 — owner: agent · verify: 三种语言的快照 · done 2026-11-27
- [x] ~~T8 接上三个统计事件~~ dropped: App 里没有上报使用行为的通道，这是单独的变更（design §6）；`ui/event.yaml` 里补了三个事件的定义

## M3 · 验证
- [x] T9 `ui/screen.yaml`、`translations.yaml`、`ScreenCatalog` 加卡片条、空白区域、顶部提示的状态 — owner: agent · verify: scripts/ui-snapshots.sh verify world_ · done 2026-11-27
  - evidence: world_、map.、share_card.、series_share_card.、series_detail. 各组都一致
- [x] T10 全部测试 — owner: agent · verify: xcodebuild test · done 2026-11-27
  - evidence: 141 项通过，2 项跳过
- [ ] T11 真机走查：打开的位置和等待、拖动和缩放的流畅度、滑动卡片时镜头的三档、把地图挪到自己有收藏而没有公开作品的地方看邀请、断网后打开 — owner: me · after: T5, T6 · verify: me 确认，或告诉 agent 哪里要调

## 附带
- [x] T12 快照测试的数据在整个测试过程中保持存活 — owner: agent · verify: 单独跑 map. 和 series_detail. 两组 · done 2026-11-27
  - evidence: 之前只跑其中一组时测试进程会崩溃（地图图钉在数据销毁后还在刷新），现在两组都通过
- [x] T13 一处作品很多时的网格面板：`WorldPostGrid`、卡片条的「查看全部」、两条新文字的翻译、图库状态 world_strip.many / world_post_grid.* — owner: agent · verify: 快照 + 模拟器 · done 2026-11-27
  - evidence: 141 项测试通过；iOS 26.3 模拟器、线上后端：缩小到一个写着 9 的标记，点它和「只看这片区域」都出现「See all」，网格显示 9 件，点鸟居那张打开详情，关掉后卡片条停在这一件、地图没动。超过 200 件和加载中的样子只有快照，没有真实数据
- [ ] T14 在 1.2.0 (125) 上真机看网格面板和自己位置的圆点：半屏拉到全屏、几十件时滚动是否顺、从详情回来的位置 — owner: me · after: T13 · verify: me 确认，或告诉 agent 哪里要调
- [x] T15 世界地图显示自己位置的圆点和定位按钮（只在已有许可时）— owner: agent · verify: 模拟器 · done 2026-11-27
  - evidence: iOS 26.3 模拟器，位置设在涩谷、已授权：右上角出现定位按钮，点它地图移到涩谷并显示圆点。没有许可时不显示这一条没有在模拟器里看，只由代码里的条件保证
