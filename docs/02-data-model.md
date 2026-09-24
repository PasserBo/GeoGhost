# GeoGhost — 数据模型

> SwiftData `@Model`。所有时间 UTC 存储，显示时本地化。

## Artwork（一件被收藏的作品，一次相遇）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 主键 |
| `createdAt` | Date | 收藏时间（App 内） |
| `capturedAt` | Date? | 拍摄时间：优先 EXIF `DateTimeOriginal`，其次快门时刻 |
| `kind` | ArtworkKind | sticker / graffiti / mural / poster / tag / other |
| `kindIsAutoDetected` | Bool | 类型是否由分类器给出 |
| `latitude` / `longitude` | Double? | WGS84；来源 GPS 或 EXIF |
| `horizontalAccuracy` | Double? | m |
| `altitude` | Double? | m |
| `heading` | Double? | 拍摄朝向（度），来自 CLHeading 或 EXIF `GPSImgDirection` |
| `locationSource` | LocationSource | device / exif / manual / none |
| `placeName` | String? | 反地理编码：`"Shibuya, Tokyo"` |
| `countryCode` | String? | ISO 3166-1 |
| `originalImageID` | String | 原图文件名（HEIC/JPEG） |
| `cutoutImageID` | String | 抠图 PNG（含 alpha） |
| `thumbnailImageID` | String | ≤ 400 px 缩略 PNG |
| `cutoutRect` | CGRect（编码为 4 Double） | 抠图在原图中的归一化位置 |
| `segmentationMode` | SegmentationMode | auto / autoAdjusted / manualCrop |
| `featurePrint` | Data? | 序列化 `VNFeaturePrintObservation` |
| `dominantColorHex` | String? | 主色，用于网格背景/排序 |
| `deviceModel` / `lensModel` | String? | EXIF |
| `imagePixelWidth/Height` | Int | 原图尺寸 |
| `note` | String | 用户备注 |
| `tags` | [Tag] | 多对多 |
| `series` | ArtSeries? | 多对一 |
| `isSeriesManuallyAssigned` | Bool | 用户手动归类后自动匹配不再覆盖 |
| `isFavorite` | Bool | |
| `visibility` | Visibility | private / public（v1.x） |

## ArtSeries（同一设计的集合）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | |
| `createdAt` | Date | |
| `title` | String? | 用户命名，默认空 → UI 显示「未命名系列 #n」 |
| `coverArtworkID` | UUID? | 封面；默认首件 |
| `artworks` | [Artwork] | 一对多，级联置空 |
| `representativeFeaturePrint` | Data? | 系列质心（v1 直接用封面的 featurePrint） |

派生数据（不存储，按需计算）：相遇次数、跨越城市数、首次/最近相遇、地理包围盒。

## Tag

| 字段 | 类型 |
|---|---|
| `name` | String（唯一，小写） |
| `artworks` | [Artwork] |

## 枚举

```swift
enum ArtworkKind: String, Codable, CaseIterable { case sticker, graffiti, mural, poster, tag, other }
enum LocationSource: String, Codable { case device, exif, manual, none }
enum SegmentationMode: String, Codable { case auto, autoAdjusted, manualCrop }
enum Visibility: String, Codable { case privateOnly, publicShared }
```

## 文件布局

```
Application Support/
└── Images/
    └── <artwork-uuid>/
        ├── original.heic
        ├── cutout.png
        └── thumb.png
```

删除 Artwork 时同步删除目录。导出 ZIP 时按此结构 + `manifest.json`。

## 迁移策略

- v1 使用 `VersionedSchema` `SchemaV1`；后续变更通过 `SchemaMigrationPlan`。
- 开启 CloudKit 后所有属性需有默认值/可选，关系需可选 —— 模型从一开始按此约束设计。
