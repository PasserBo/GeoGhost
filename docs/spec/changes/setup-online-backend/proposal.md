# Proposal: 为线上功能准备后端（账号认证、数据、图片存储）

> State: in-progress · Updated: 2026-11-12

## Intent
阶段 1 的发布、Explore、点赞、举报都需要一个后端。这个变更只搭基础设施和共用契约，用户看不到任何变化；完成的标志是一次端到端冒烟测试通过：匿名登录 → 建资料 → 建帖子 → 上传图片 → 在 Explore 查询里看到它。

## Scope
In scope:
- Supabase 项目：匿名认证、表、权限规则、额度与阈值配置、RPC。
- Cloudflare R2 bucket 与上传 Worker（校验身份、归属、大小、格式）。
- App 读取线上配置；未配置时线上功能整体隐藏。
- 端到端冒烟测试脚本。
Out of scope:
- 任何界面（由 2–6 号变更各自负责）。
- App Attest、DeviceCheck、自有域名（design §9）。

## Capabilities
- 无（基础设施，没有行为变化，所以没有 delta）。

## Decisions
- 2026-11-09: 后端用 Supabase（认证 + Postgres），图片放 Cloudflare R2 — 地图聚合与审核查询用 SQL；R2 下行流量免费（ADR-007）。
- 2026-11-12: 图片只经 Worker 上传，客户端不持有 R2 凭证 — 上传时就能校验归属、大小和格式。
- 2026-11-12: 客户端不引入第三方 SDK，Auth / PostgREST / Worker 都用 URLSession 直接调用 — 保持零依赖原则（ADR-001 起的约定）。
- 2026-11-12: MVP 阶段图片由 Worker 读 R2 返回；买自有域名后改为 R2 自定义域名，客户端只换配置 — Worker 免费额度每天 10 万次请求，早期足够。
- 2026-11-12: Supabase 选东京（ap-northeast-1），虽然 App 面向全球 — 早期用户和种子内容在日本；数据量最大的图片走 Cloudflare 边缘缓存，与数据库区域无关；远距离用户只在小体积的查询上多一次往返，之后可用边缘缓存 explore 结果或只读副本补上；日本有欧盟充分性认定，欧洲用户数据存放在日本合规成本低。

- 2026-11-12: 暂不购买自有域名 — 图片继续由 Worker 返回，早期的免费额度足够。

## Open questions

## Links
- Design: [design.md](design.md) · ADR: [ADR-007](../../../01-technical-architecture.md) · 身份设计: [09](../../../09-online-identity.md)
