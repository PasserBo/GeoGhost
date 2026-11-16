# UI 管理

行为由 `docs/spec/` 管，界面由这个目录管。目标是：界面不会在没人注意的情况下走样，而且不开 Xcode 的人也能随时看到每个屏幕现在的样子。

| 文件 | 作用 |
|---|---|
| `screen.yaml` | 屏幕清单：每个屏幕、弹层、关键组件，以及各自的状态 |
| `event.yaml` | 事件清单：值得统计的用户行为，只能引用 `screen.yaml` 里的屏幕（目前只是定义，尚未上报） |
| `snapshots/` | 基准图：每个状态渲染出来的图片，由测试生成，提交进仓库 |

网页图库：<https://passerbo.github.io/GeoGhost/ui/>（合并到 main 后自动更新）。

## 它怎么防止界面走样

1. `GeoGhostTests/UISnapshots/UISnapshotTests` 按 `screen.yaml` 把每个状态渲染成图片，与 `snapshots/` 里的基准图比对，不一样就失败。
2. 渲染用的是固定数据（`UIFixtures.swift`）：同样的贴纸、日期、时区，图案是程序画的占位贴纸。所以两张图不同，只可能是界面变了。
3. 改了界面，基准图的变化会出现在提交里。在 GitHub 的 Files changed 里可以并排、滑动、叠加三种方式看前后对比。

## 日常操作

```sh
scripts/ui-snapshots.sh verify   # 比对；有差异就失败
scripts/ui-snapshots.sh record   # 界面是有意改的：重新录制全部基准图，然后比对一次
ruby scripts/build-ui-gallery.rb build/ui-gallery && open build/ui-gallery/index.html   # 本地看图库
```

基准图依赖模拟器型号和 iOS 版本，只在 `screen.yaml` 的 `matrix` 指定的模拟器、语言和地区下录制和比对。直接在 Xcode 里跑测试时，条件不符这项比对会跳过，所以要用上面的脚本。升级 Xcode 大版本后要整体重录一次。

## 加一个屏幕或状态

1. 在 `screen.yaml` 里加上屏幕或状态，写明用哪份 fixture。
2. 在 `GeoGhostTests/UISnapshots/ScreenCatalog.swift` 里加一条，说明怎么用 fixture 把它摆出来。
3. 需要新的数据场景时，在 `UIFixtures.swift` 里加一份 fixture。
4. 运行 `scripts/ui-snapshots.sh record`，看一眼新图，提交。

测试会检查：`screen.yaml` 和 `ScreenCatalog` 两边一致；`event.yaml` 引用的屏幕都存在；`snapshots/` 里没有多余或缺少的图。

## 截图的组合

主语言（`matrix.primary_locale`）：全部状态 × 浅色和深色。其余语言：每个屏幕的默认状态 × 浅色，用来发现文字放不下的问题。

## 暂时截不了的状态

`screen.yaml` 里 `snapshot: false` 的状态都写了原因，主要是三类：含地图（瓦片每次不同）、依赖相机或系统权限、内容来自服务器或要先点几下才能到达。它们仍然列在清单里，图库里会显示原因。要补上，需要先让对应的屏幕能从外部注入固定内容。

系统自己画、每次不一定相同的小区域（收藏页的搜索栏文字、反馈页里的构建号）用 `unstable` 声明，比对时跳过，图库里的图不受影响。
