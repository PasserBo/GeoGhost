# Design: add-explore-map

- **入口**：`ArtMapView` 顶部分段控件（「我的 / 世界」），选择存在 `@AppStorage("mapMode")`；没有线上配置的构建不显示切换。
- **数据**：`ExploreModel`（已完成，`GeoGhost/Services/Explore/`）：视口变化去抖 350 ms，只让最新请求生效，按网格取整的区域缓存 60 s；`ExploreGrid` 按纬度跨度选网格（约 8 格，2 的幂），跨度 < 0.03°（约 3 km）时返回单张。
- **显示**：`cellCount > 1` 画聚合（数量 + 代表缩略图），点按把镜头移到该格中心、跨度缩为 1/4；`cellCount == 1` 画缩略图标注，点按打开 `RemotePostSheet`。
- **图片**：缩略图 / 大图来自 `OnlineConfig.imageURL(key:)`，iOS 原生可解 HEIC；`RemoteImageView` 用内存缓存（`NSCache`）+ URLSession，失败显示占位。
- **身份**：`ExploreClient` 以 `.ifPresent` 调用，浏览不创建游客（`online-identity` › 浏览不需要身份）。
