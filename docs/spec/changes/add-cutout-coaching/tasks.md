# Tasks: add-cutout-coaching

## Now
2026-11-19：T1–T4 完成（agent）。T5 示例照片练习等 me 提供 2–3 张照片；T6 真机。

## M1 · 规格
- [x] T1 delta `capture-editor`（手势演示、基本操作、取景提示框） — owner: agent · verify: check-delta 无错误 · 证据：check-delta 无输出

## M2 · 客户端
- [x] T2 编辑器手势演示（前三次 + 第一次失败后） — owner: agent · after: T1 · verify: 构建；模拟器 · 证据：单元测试通过；模拟器 4F71E5A0 打开编辑器显示手指画虚线圈的动画
- [x] T3 手势说明「基本操作」一组 — owner: agent · after: T1 · verify: 构建
- [x] T4 取景框静态提示框 — owner: agent · after: T1 · verify: 构建（模拟器没有相机，需真机看）
- [ ] T5 示例照片练习：空图鉴「用示例照片试试」→ 编辑器；练完不存，引导去拍 / 选自己的照片 — owner: agent · after: me 提供照片 · verify: 模拟器
- [ ] T6 提供 2–3 张自己拍的贴纸照片（由易到难） — owner: me
- [ ] T7 真机：演示、取景框、示例练习 — owner: me · after: T5
