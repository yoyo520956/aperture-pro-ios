# Aperture Pro（光圈Pro）v1.1.0

中式审美相机 App：意境留白 · 宣纸米白 / 青黛 / 朱砂 · 苹果组件行为不动。

## 功能
- 拍照 / 录像 / 4K / 慢动作(120fps) / 延时摄影 / 夜景(长曝光+HDR) / Live Photo
- Pro 手动：ISO / 快门 / 曝光补偿 / 白平衡（轻调藏而不露）
- 全景横滑拼接（25% 重叠交叉淡化）
- 文档扫描（VisionKit 取景 + 透视矫正 + 黑白/宣纸风 + PDF 导出）
- 滤镜 8 种 + 裁剪 / 旋转 / 调色（亮度/对比/饱和）
- 系统相册读写（PHPhotoLibrary）+ 长图拼接
- 定时快门 3/5/10s · 电子稳定器 · 闪光灯
- iCloud 同步（NSUbiquitousContainer + BGTaskScheduler）
- AR 面部追踪 / IP 推流 / 频闪摄影 / 扫码 / 视频编辑
- 桌面小组件（深链 aperturepro://）+ 系统分享扩展

## 构建
GitHub Actions（macos-15）：xcodegen → xcodebuild → 未签 IPA + UTF-8 特征串核验。
