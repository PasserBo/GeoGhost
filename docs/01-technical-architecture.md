# GeoGhost — 技术架构

> 状态：v1.0 · 2026-09-24

## 1. 技术选型总览

| 层 | 选择 | 理由 |
|---|---|---|
| 平台 | **iOS 17.0+，原生 Swift 6 / SwiftUI** | 核心能力（实例分割、FeaturePrint、SwiftData）都是 iOS 17 起的系统框架；Flutter 需要为每一项写平台通道，且 ML Kit 无模拟器切片曾导致开发体验极差 |
| UI | SwiftUI + 少量 UIKit 桥接（相机预览、分割编辑器手势） | |
| 架构 | MVVM + 领域服务层（Services），`@Observable` 状态 | 轻量、可测试；不引入第三方状态库 |
| 持久化 | **SwiftData**（本地）→ 开启 CloudKit 私有库镜像（Pro 功能） | 系统方案，零运维，自动同步 |
| 图像存储 | 文件系统（`Application Support/Images/<uuid>/`），数据库只存相对路径 | 大二进制不进 SQLite；iCloud 同步时走 `CKAsset` |
| 分割 | **Vision `VNGenerateForegroundInstanceMaskRequest`**（iOS 17） | 端侧、多实例、高质量 alpha mask；支持点选实例 |
| 相似度/系列 | **Vision `VNGenerateImageFeaturePrintRequest`** + 距离阈值聚类 | 端侧，2048 维向量，同设计不同角度/光照鲁棒 |
| 分类 | Vision `VNClassifyImageRequest` 关键词映射（v1），后续可换自训 Core ML | 零成本起步 |
| 相机 | AVFoundation `AVCapturePhotoOutput`，写入 EXIF/GPS | 完整控制元数据 |
| 元数据 | ImageIO `CGImageSource` 读取 EXIF/GPS/TIFF；`CLGeocoder` 反地理编码 | |
| 地图 | **MapKit（SwiftUI `Map`）**，自研网格聚合 | 无 API key，无费用 |
| 后端 | **无自建服务器。CloudKit**：v1 私有库同步；v1.x 公共库做公开地图 | 零运维、免费额度足够、身份即 iCloud |
| 支付 | StoreKit 2，非消耗型「Pro」 | |
| 项目生成 | XcodeGen (`project.yml`) | pbxproj 不手写，可 diff、可 review |
| 依赖 | **零第三方依赖**（v1） | 减少审核/维护风险 |
| 测试 | XCTest：服务层单测（元数据解析、聚类阈值、存储）+ 少量 UI 冒烟 | |

## 2. 模块划分

```
GeoGhost/
├── App/                    入口、根导航、全局环境（AppEnvironment）
├── Domain/
│   ├── Models/             SwiftData @Model：Artwork, ArtSeries, Tag
│   └── ValueTypes/         ArtworkKind, CaptureMetadata, GeoPoint ...
├── Services/
│   ├── Camera/             CameraService (AVFoundation)、CameraPreviewView
│   ├── Location/           LocationService (CLLocationManager, 单次定位 + 朝向)
│   ├── Imaging/            SegmentationService (Vision)、ImageStore、ImageMetadataReader、ImageExporter
│   ├── Matching/           FeaturePrintService、SeriesMatcher（聚类）
│   ├── Geocoding/          ReverseGeocoder（带缓存、限流）
│   └── Store/              ProStore (StoreKit 2)
├── Features/
│   ├── Capture/            CaptureView（相机）→ SegmentationEditorView → SaveSheet
│   ├── Collection/         CollectionView（贴纸网格）、ArtworkDetailView
│   ├── Series/             SeriesListView、SeriesDetailView（多点地图连线）
│   ├── Map/                ArtMapView（聚合）
│   └── Settings/           SettingsView（Pro、iCloud、导出、隐私、关于）
├── DesignSystem/           颜色、字体、纸张背景、StickerCard、Chip 等组件
└── Resources/              Assets、Localizable.xcstrings、PrivacyInfo.xcprivacy
```

**依赖方向**：Features → Services → Domain。Services 之间不互相依赖（由 Feature 的 ViewModel 编排）。

## 3. 关键流程

### 3.1 采集管线（详见 [03-capture-pipeline.md](03-capture-pipeline.md)）

```
快门 ──► AVCapturePhoto(含GPS/EXIF) ──► 落盘原图(HEIC)
                                    └─► SegmentationService.analyze()
                                            │  VNGenerateForegroundInstanceMaskRequest
                                            ▼
                                    InstanceMaskResult{ instances, defaultSelection }
                                            │  用户点选/多选 (SegmentationEditorView)
                                            ▼
                                    cutout PNG(alpha) + thumbnail ──► ImageStore
                                            │
                                            ├─► FeaturePrintService ──► SeriesMatcher ──► 归入/新建 ArtSeries
                                            ├─► ClassifierService  ──► kind 建议
                                            └─► ReverseGeocoder    ──► placeName (异步补全)
                                            ▼
                                    Artwork 写入 SwiftData
```

### 3.2 系列匹配

- 每件作品在保存时计算 `VNFeaturePrintObservation`（对**抠图**而非原图计算，去除背景干扰），序列化为 `Data` 存入 `Artwork.featurePrint`。
- 匹配：与库中所有作品做 `computeDistance`，取最小距离；`< 0.55` 判为同系列（阈值可在设置中调「严格/宽松」，并用真实样本回归校准）。
- 复杂度 O(n)，n ≤ 数千件时端侧毫秒级；超过 1 万件再考虑 LSH。
- 用户可手动「移出系列」「合并系列」；手动操作记录 `isManuallyAssigned`，之后自动匹配不再覆盖。

### 3.3 同步（Pro）

- SwiftData `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.passerbo.geoghost"))`。
- 图片文件：作为独立 `CKAsset` 记录同步，SwiftData 只存 `imageID`；实现 `ImageSyncService` 负责按需上传/下载。
- 冲突策略：last-writer-wins；图片不可变（只增不改），天然无冲突。

## 4. 性能预算

| 操作 | 目标 | 手段 |
|---|---|---|
| 快门 → 分割结果显示 | ≤ 1.0 s | 分割输入降采样至 1024 px 长边；mask 上采样回原图仅在保存时进行 |
| 图鉴网格滚动 | 60 fps | 缩略图 ≤ 400 px PNG，`LazyVGrid` + 磁盘缓存 |
| 冷启动 | ≤ 1.5 s | 相机会话在 `onAppear` 后台线程配置；地图页懒加载 |
| 内存 | 相机 + 分割峰值 < 300 MB | 原图 HEIC 落盘后立即释放 `CGImage`；用 `CIContext` 复用 |

## 5. 错误处理与降级

- 分割无实例：进入手动裁切模式（矩形 + 可调四角），仍可保存。
- 无定位权限/无 GPS：允许保存，位置为空，后续可在地图上长按手动标记。
- 反地理编码失败：静默重试 3 次（指数退避），显示坐标。
- 存储空间不足：保存前检查 `volumeAvailableCapacityForImportantUsage`，不足 200 MB 提示。

## 6. 安全与隐私实现

- `PrivacyInfo.xcprivacy`：声明 `NSPrivacyAccessedAPICategoryFileTimestamp`（C617.1）、`UserDefaults`（CA92.1）；不采集追踪数据。
- Info.plist：`NSCameraUsageDescription`、`NSLocationWhenInUseUsageDescription`；**不申请**相册读权限（用 `PhotosPicker`），保存到相册用 `PHPhotoLibrary` add-only 权限。
- 日志不含坐标与图像。

## 7. 架构决策记录（ADR）

- **ADR-001 放弃 Flutter 改原生**：分割/FeaturePrint/SwiftData/MapKit 全是系统框架，Flutter 无等价物；ML Kit 模拟器不可用已严重拖慢迭代；App 定位单平台精品。代价：放弃 Android，v1 可接受。
- **ADR-002 无自建后端**：v1 单人本地 + iCloud；多人阶段用 CloudKit Public DB。避免服务器成本与隐私合规负担；缺点是难以做跨平台/Web，接受。
- **ADR-003 对抠图而非原图计算 FeaturePrint**：原图背景（墙面、杆子）会主导相似度；抠图后同设计贴纸距离显著缩小。
- **ADR-004 图片走文件系统**：SwiftData/CloudKit 对大 blob 支持弱；文件 + 相对路径最稳。
- **ADR-005 iOS 17 为最低版本**：`VNGenerateForegroundInstanceMaskRequest` 与 SwiftData 均需 17；2026 年 iOS 17+ 覆盖率 > 95%。
