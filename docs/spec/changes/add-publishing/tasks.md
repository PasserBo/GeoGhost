# Tasks: add-publishing

## Now
发布服务完成（T1–T4）：`ArtworkPublisher` + `PublishClient`，真实后端已验证。下一步是界面：T5 详情页入口、T6 发布预览（首次发布先走 add-guest-identity 的昵称与规则页）、T7 状态与撤回。

## M1 · 基础
- [x] T1 发布用图片编码：长边 1024 与 400 两张、保留透明、不含任何元数据 — owner: agent · verify: 单元测试（尺寸、透明、无 GPS/EXIF/TIFF） · done 2026-11-12
  - evidence: `PublishImageEncoderTests`（2 个：1024/400、透明保留、无 GPS/EXIF/IPTC、不放大小图）
- [x] T2 坐标模糊（约 100 m 网格，与服务端同一公式） — owner: agent · verify: 单元测试 · done 2026-11-12
  - evidence: `LocationBlurTests`（2 个：已知坐标、1000 个随机点幂等且误差 ≤ 半格）
- [x] T3 本地模型：发布状态、线上帖子 ID、发布时间（轻量迁移） — owner: agent · verify: 单元测试（旧数据打开后为「未发布」） · done 2026-11-12
  - evidence: `ArtworkPublishStateTests`；模拟器上旧数据（2 件）用新构建打开正常
- [x] T4 发布服务：create_post → 上传 → 写回状态；失败可重试；撤回；撤回全部；状态同步 — owner: agent · after: T1–T3, add-guest-identity T3–T4 · verify: 单元测试（替身后端） · done 2026-11-12
  - evidence: `ArtworkPublisherTests`（9 个：只发公开字段、新用户审核中、已信任直接公开、无位置不能发布、中断后重试只占一次额度、上传成功但回应丢失不重传、被拒保持私密、撤回后再发是新帖、撤回全部、状态同步）+ `PublishClientTests`（4 个）；`LiveBackendTests` 在真实后端通过

## M2 · 界面
- [ ] T5 详情页发布入口（无位置时不可用并说明） — owner: agent · after: T3 · verify: 模拟器截图
- [ ] T6 发布预览页：抠图、区域、日期、昵称、隐私说明、剩余额度；首次发布先走昵称与规则页 — owner: agent · after: T4, add-guest-identity T6 · verify: 模拟器截图
- [ ] T7 发布状态显示（审核中 / 已公开 / 未通过 / 未完成 + 重试）与撤回 — owner: agent · after: T4 · verify: 模拟器截图
- [ ] T8 额度用完与离线的提示 — owner: agent · after: T4 · verify: 单元测试 + 模拟器
- [ ] T9 设置页「撤回全部公开内容」；删除已公开贴纸时的确认与撤回 — owner: agent · after: T4 · verify: 模拟器

## M3 · 验证
- [ ] T10 真实后端端到端：发布 → 审核中 → 在 Supabase 里审核通过 → 已公开 → 撤回 — owner: agent · after: setup-online-backend T11 · verify: 测试输出 + 截图
  - 2026-11-12 `LiveBackendTests`（`TEST_RUNNER_GG_LIVE_TESTS=1`）已在真实后端跑通 发布 → 审核中 → 同步 → 撤回；还差「在 Supabase 里审核通过 → 已公开」与截图，等 T5–T7 界面完成后一起做。
- [ ] T11 真机发布 3 张并审核 — owner: me · after: T10 · verify: 真机通过
