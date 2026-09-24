# GeoGhost — 采集与分割管线

> 这是产品最关键的一条路径。目标：**快门 → 看到抠图 ≤ 1 s；≤ 3 次点击完成收藏。**

## 1. 输入源

| 来源 | 图像 | 位置 | 时间 | 其他元数据 |
|---|---|---|---|---|
| App 内相机 | `AVCapturePhoto` HEIC | `CLLocationManager` 快门时刻最近一次 fix（≤ 10 s 内，精度 ≤ 65 m 才采用） | 快门时刻 | `CLHeading` 朝向、设备型号、镜头（`AVCaptureDevice.deviceType`） |
| 相册导入 (`PhotosPicker`) | 原始 Data（保留 EXIF） | EXIF GPS（`kCGImagePropertyGPSDictionary`） | EXIF `DateTimeOriginal` + `OffsetTimeOriginal` | `TIFF.Model`、`Exif.LensModel`、`GPSImgDirection`、方向（Orientation） |

相机拍摄时通过 `AVCapturePhotoSettings.metadata` 写入 GPS 字典，落盘的原图本身就带完整 EXIF，与相册导入路径统一。

## 2. 分割

### 2.1 主路径：`VNGenerateForegroundInstanceMaskRequest`

1. 原图降采样到长边 1024 px 的 `CIImage`（保留 EXIF 方向，先 `oriented(.up)`）。
2. 执行请求，得到 `VNInstanceMaskObservation`：
   - `allInstances: IndexSet`
   - `instanceMask` (每像素 instance index 的 `CVPixelBuffer`)
3. **默认选择策略**：
   - 若只有 1 个实例 → 直接选中。
   - 多个实例 → 选中**包含画面中心点**的实例；若中心无实例，选面积最大者。
4. 用户交互（`SegmentationEditorView`）：
   - 点击像素 → 查 `instanceMask` 该点的 instance index → toggle 选中集合。
   - 未选中区域压暗 60% + 选中区域描边（高亮 marching-ants 风格描边）。
   - 底部条：「重选」「手动裁切」「收藏」。
5. 生成结果：`generateMaskedImage(ofInstances:from:croppedToInstancesExtent: true)` 在**全分辨率**原图上执行（此时把 `VNImageRequestHandler` 换成原图），得到带 alpha 的 `CVPixelBuffer` → PNG。
6. 边缘处理：对 mask 做 1 px 高斯羽化（`CIGaussianBlur` radius 0.8）再合成，避免锯齿。

### 2.2 回退：手动裁切

- 触发：无实例 / 用户点「手动裁切」。
- UI：矩形 + 四角可拖动（后续可加套索）。
- 产物：矩形裁切的**不透明** PNG；`segmentationMode = .manualCrop`。图鉴中以圆角卡片显示，与透明贴纸区分。

### 2.3 质量守卫

- 选中实例面积 < 原图 0.5% → 提示「太小，建议靠近拍摄」但允许保存。
- 选中实例触及画面 4 边中的 ≥ 3 边 → 可能是整面墙（壁画），自动建议 `kind = .mural`，且不建议裁切。

## 3. 保存

```
SaveSheet 展示：
  [抠图预览, 透明棋盘背景]
  类型   ● 贴纸  ○ 涂鸦  ○ 壁画  ○ 海报  ○ Tag  ○ 其他   （分类器预选）
  地点   Shibuya, Tokyo（自动，正在获取…）
  时间   2026-09-24 14:32
  备注   ______
  标签   #___
  [ 收藏 ]
```

保存顺序（全部在 `Task.detached(priority: .userInitiated)`）：

1. 建目录 `Images/<uuid>/`，写 `original.heic`（原 Data，不重编码，保留 EXIF）。
2. 写 `cutout.png`、`thumb.png`（长边 400，`CGImageDestination` PNG，保留 alpha）。
3. `Artwork` 插入 `ModelContext` → **UI 立刻返回图鉴**。
4. 后台继续：FeaturePrint → SeriesMatcher → 更新 `series`；分类器 → 若用户未手动改类型则更新 `kind`；反地理编码 → `placeName`。每步单独 `save()`，界面通过 SwiftData 观察自动刷新。

## 4. 系列匹配细节

- 输入：抠图（不含背景），缩放到 224–512 px。
- `VNGenerateImageFeaturePrintRequest`，`imageCropAndScaleOption = .scaleFit`，用透明 → 中性灰底填充（避免 alpha 被当黑）。
- 距离：`observation.computeDistance(&d, to: other)`；阈值默认 `0.55`（经验值，FeaturePrint v2 同物体不同视角通常 < 0.4，不同物体 > 0.8；需用真实贴纸集回归）。
- 若最小距离落在 `[0.55, 0.75)` 的灰区 → 保存后在详情页给出「这可能和 ×× 是同一张？」的可确认建议，用户点确认后归入并把该对样本记录到本地校准集。

## 5. 分类器（kind 建议）

v1 使用 `VNClassifyImageRequest` 的 1303 类标签做关键词映射：

| 标签命中 | kind |
|---|---|
| sticker, label, decal, badge, emblem | sticker |
| graffiti, spray_paint, wall, street_art | graffiti |
| mural, painting（且面积规则命中） | mural |
| poster, flyer, billboard, sign | poster |
| text, handwriting, calligraphy | tag |
| 其他 | sticker（默认，因为最高频） |

置信度 < 0.3 时不预选，UI 默认「贴纸」。v1.1 用收集到的样本训练 Create ML 图像分类器替换。

## 6. 错误矩阵

| 情况 | 行为 |
|---|---|
| 相机不可用（模拟器/权限拒绝） | 采集页显示引导 + 「从相册导入」按钮 |
| 定位拒绝 | 正常保存，地点空；详情页可手动在地图上放置 |
| Vision 抛错 | 直接进入手动裁切 |
| 磁盘不足 | 保存前阻断并提示 |
| 图片无 EXIF 时间（截图/网络图） | 用导入时刻，并在详情标注「时间为导入时间」 |

## 7. 测试要点

- `ImageMetadataReader`：给定含 GPS/无 GPS/带时区偏移的 3 张固定 JPEG，断言解析结果。
- `SeriesMatcher`：固定 5 张同贴纸 + 5 张不同贴纸的 FeaturePrint 快照（Data），断言聚类正确。
- `ImageStore`：写入/删除/目录清理。
- 分割仅做集成冒烟（模拟器可运行 Vision）。
