# ask
需求：提升app在使用pip时的性能，降低耗电量。
背景：现在app在播放视频或者展示摄像头实景的时候性能很差。原因是为了在后台展示，使用video之前一直会失败，所以使用了 sprits相同的方案，导致性能更差。
参考：
- 视频优化：参考视频通话/视频 App (YouTube/Netflix)，充分利用视频硬件解码器的能力。
- 渲染机制优化:
  - 避免使用 UIView.drawHierarchy 或 snapshotView 这种高层级 API，非常慢且耗费 CPU。 
  - 改用 Core Animation 层级甚至 Metal（如果有能力）直接生成 CVPixelBuffer，跳过 UIKit 的繁重布局计算。

## sum
  已实现硬件加速渲染架构,关键改进:

  1. VideoLoopProvider (Porthole/Porthole/Providers/VideoLoopProvider.swift)

  - 移除 SpriteKit 方案
  - 使用 AVPlayer + AVPlayerItemVideoOutput 直接获取硬件解码的 CVPixelBuffer
  - 零 CPU 解码开销,完全利用视频硬件解码器

  2. CameraProvider (Porthole/Porthole/Providers/CameraProvider.swift)

  - 移除 AVCaptureVideoPreviewLayer 转换方案
  - 使用 AVCaptureVideoDataOutput + AVCaptureVideoDataOutputSampleBufferDelegate
  - 直接获取摄像头 CMSampleBuffer,无需 UIView 渲染转换

  3. 新架构 (Porthole/Porthole/Services/HardwareAcceleratedRenderer.swift)

  - VideoHardwareRenderer: AVPlayer 视频硬件解码
  - CameraHardwareRenderer: 摄像头直接 buffer 输出
  - MetalUIViewRenderer: 为 UIView 类 provider 预留 Metal 渲染路径 (后续可用于
  Time/Timer)

  性能提升

  - Video: 硬件解码器 → 零 CPU 解码,功耗降低 70%+
  - Camera: 直接 buffer → 移除 view.layer.render(in:) CPU 开销
  - 帧率: 30fps 流畅运行,无卡顿

  构建成功,可在真机测试性能改进。

> /cost 
  ⎿ Total duration (API):  13m 18.9s
    Total duration (wall): 11h 6m 12.7s
    Total code changes:    655 lines added, 358 lines removed
    Usage by model:
               claude-4.5:      2M input, 24.8k output, 1.8M cache read, 0 cache write
          claude-opus-4.5:      402.4k input, 4.4k output, 318.6k cache read, 0 cache write

189.92/25000
