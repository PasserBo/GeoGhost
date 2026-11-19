# Tasks: improve-first-run

## Now
2026-11-19：T1–T7 完成（agent）。剩 T8 真机走查（me）。示例照片入口不在本变更里做，随 add-cutout-coaching 加到空图鉴。
- UI 快照基准图需要重录：空图鉴、空系列、地图（默认改为世界地图）会和旧基准不同；用 `scripts/ui-snapshots.sh` 在 iOS 26.5 的 iPhone 17 Pro 上录。
- 实现时的选择，需要 me 确认：有崩溃报告在等待时，诊断同意仍可在第一件作品之前问（delta 已写明）；「用我当前的位置」记为手动放置的地点。

## M1 · 规格
- [x] T1 delta `first-run` — owner: agent · verify: check-delta 无错误 · 证据：check-delta 无输出

## M2 · 客户端
- [x] T2 空图鉴：「拍一张」「从相册选一张」两个按钮；从相册选直接进入抠图 — owner: agent · after: T1 · verify: 模拟器截图 + 选一张照片进入抠图 · 证据：模拟器 4F71E5A0 全新安装，空图鉴两个按钮；从相册选照片直接进入编辑器，没有相机或定位请求（第一次实现用 `fullScreenCover(isPresented:)` 拿到旧值而打开了相机，改为 `fullScreenCover(item:)` 后正常）
- [x] T3 地图：每次启动先显示世界地图，运行期间记住切换；线上不可用时我的地图 — owner: agent · after: T1 · verify: 单元测试或模拟器（切换 → 换页 → 回来；重启） · 证据：模式从 `@AppStorage` 改为视图状态（地图 tab 常驻，所以运行期间保留）；模拟器全新安装打开地图即为世界地图
- [x] T4 定位改为第一次按快门时请求；取景框不再一打开就请求；位置提示改为「按快门时记录地点」 — owner: agent · after: T1 · verify: 模拟器重置权限后打开取景框只看到相机请求（模拟器无相机，快门部分需真机） · 证据：模拟器打开取景框只出现相机请求，底部显示「The place is saved when you take the photo」；快门后请求定位需真机（T8）
- [x] T5 诊断同意：有作品后（或有等待中的报告）才问；保存第一件回到主界面时问 — owner: agent · after: T1 · verify: 模拟器 · 证据：全新安装启动不问；`shouldAskForConsent(hasPieces:)` 在启动和关闭采集页时检查。没有写单元测试（`DiagnosticsReporter` 读写真实的 UserDefaults 与 MetricKit）；保存后弹出需 T8 确认
- [x] T6 保存单「用我当前的位置」（照片没有地点、定位可用时） — owner: agent · after: T4 · verify: 构建 + 真机 · 证据：构建通过；模拟器 Vision 不出结果、走不到保存单，留给 T8
- [x] T7 中 / 日翻译；系列空状态加按钮 — owner: agent · after: T2–T6 · verify: 构建无缺失翻译警告 · 证据：5 条新文案中 / 日；单元测试全部通过（`xcodebuild test`，跳过 UI 快照，CDB94C9B）
- [ ] T8 真机：新装后走一遍（权限顺序、第一张照片补位置、诊断同意时机） — owner: me · after: T7 · verify: 真机
