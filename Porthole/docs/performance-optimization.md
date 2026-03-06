# PiP 性能优化指南

本文档记录 Porthole 应用中针对 Picture-in-Picture (PiP) 功能的性能优化措施。

## 优化概述

PiP 功能的核心挑战是在保持流畅显示的同时最小化 CPU 和电量消耗。不同类型的内容需要不同的渲染策略。

## 已实施的优化

### 1. Provider 分类架构

根据内容特性将 Provider 分为两类：

| 类型 | 协议 | 渲染方式 | 适用场景 |
|------|------|----------|----------|
| 直接视频输出 | `DirectVideoProvider` | 直接输出帧到 `AVSampleBufferDisplayLayer` | Camera、Video、Timer、Clock |
| UIView 捕获 | `PiPContentProvider` | 通过 `ViewToVideoStreamConverter` 捕获 | 复杂动画内容 |

**优化效果**：直接视频输出绕过 UIView 渲染层级，大幅减少 CPU 开销。

### 2. CameraHardwareRenderer 优化

**问题**：摄像头输出比例（4:3）与 PiP 窗口比例（2:1）不匹配，导致黑边和尺寸不固定。

**解决方案**：
- 添加固定输出尺寸 400x200（2:1 比例）
- 使用 `CIContext` + Metal 进行 GPU 加速的 cover-style 裁剪
- 缓存裁剪和缩放变换矩阵，避免每帧重复计算
- 使用 `CVPixelBufferPool` 复用缓冲区

**关键代码** (`HardwareAcceleratedRenderer.swift:CameraHardwareRenderer`)：
```swift
// 固定输出尺寸
private static let outputWidth: Int = 400
private static let outputHeight: Int = 200

// GPU 加速处理
private let ciContext: CIContext  // Metal 加速

// 缓存变换矩阵
private var cachedCropRect: CGRect?
private var cachedScaleTransform: CGAffineTransform?
```

### 3. TextHardwareRenderer 优化

**问题**：时钟/计时器使用 `ViewToVideoStreamConverter`，每帧调用 `view.layer.render()` 导致高 CPU 占用。

**解决方案**：
- 新增 `TextHardwareRenderer` 专门渲染文本内容
- 使用 Core Graphics 直接渲染文本到 pixel buffer
- 使用 `Timer` 替代 `CADisplayLink`，减少 CPU 唤醒
- 仅在文本变化时重新渲染

**关键代码** (`HardwareAcceleratedRenderer.swift:TextHardwareRenderer`)：
```swift
// 使用 Timer 而非 CADisplayLink
timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(frameRate), repeats: true) { ... }

// 直接渲染文本到 pixel buffer
private func renderTextToPixelBuffer(_ text: String) -> CVPixelBuffer? {
    // Core Graphics 渲染，绕过 UIKit
    attributedString.draw(in: rect)
}
```

### 4. VideoHardwareRenderer 优化

- 固定输出尺寸 400x200
- 帧率控制（默认 15fps）
- 缓存旋转、裁剪、缩放变换矩阵
- GPU 加速的视频帧处理

### 5. 通用优化措施

| 优化项 | 说明 |
|--------|------|
| CVPixelBufferPool | 所有渲染器使用 buffer pool 复用内存 |
| 帧率控制 | 静态内容 1fps，动画内容 15-30fps |
| 变换矩阵缓存 | 避免每帧重复计算几何变换 |
| CGColorSpace 缓存 | 避免每帧创建 color space |
| 固定输出分辨率 | 统一 400x200，避免高分辨率带来的开销 |

## 性能对比

| Provider | 优化前 | 优化后 | 改善 |
|----------|--------|--------|------|
| Camera | 中等 CPU | 低 CPU | GPU 加速裁剪 |
| Video | 低 CPU | 低 CPU | 已优化 |
| Timer/Clock | 高 CPU | 低 CPU | 绕过 UIView 渲染 |
| Cat GIF | 中等 CPU | 中等 CPU | 延迟加载帧 |

## 后续优化方向

### 短期优化

1. **CatCompanionProvider 升级为 DirectVideoProvider**
   - 当前仍使用 UIImageView + CADisplayLink
   - 可改为直接渲染 GIF 帧到 pixel buffer
   - 预期收益：减少 UIKit 层开销

2. **文本渲染缓存**
   - 当文本未变化时复用上一帧的 pixel buffer
   - 避免重复渲染相同内容
   - 适用于时钟秒数未变化的情况

3. **屏幕关闭检测优化**
   - 当前使用 Timer 定期检测
   - 可改为监听系统通知
   - 减少后台 CPU 唤醒

### 中期优化

4. **Metal Shader 直接渲染文本**
   - 使用 Metal 渲染文本替代 Core Graphics
   - 完全 GPU 化文本渲染
   - 适用于需要更高帧率的场景

5. **自适应帧率**
   - 根据内容变化动态调整帧率
   - 静止时降至最低帧率
   - 动画时自动提升帧率

6. **电量感知调度**
   - 低电量时降低帧率和分辨率
   - 充电时恢复正常质量

### 长期优化

7. **预渲染帧缓存**
   - 对于可预测的内容（如时钟），预渲染未来几秒的帧
   - 减少实时渲染开销

8. **视频编码输出**
   - 对于静态或低变化内容，考虑输出压缩视频流
   - 利用硬件解码器播放，进一步降低 CPU 占用

9. **多 Provider 共享渲染资源**
   - 统一管理 pixel buffer pool
   - 共享 Metal device 和 command queue
   - 减少资源重复创建

## 调试与监控

### 性能监控点

```swift
// 帧率监控
if frameCount % 60 == 0 {
    print("[Renderer] Frame \(frameCount), layer status: \(displayLayer.status.rawValue)")
}

// CPU 使用监控
// 使用 Instruments > Time Profiler 分析热点
```

### 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| PiP 黑屏 | displayLayer.status == .failed | 调用 `displayLayer.flush()` |
| 高 CPU | 帧率过高或使用 UIView 渲染 | 降低帧率或切换到直接渲染 |
| 内存增长 | Pixel buffer 泄漏 | 检查 pool 使用和 buffer 释放 |
| 卡顿 | 主线程阻塞 | 将渲染移到后台队列 |

## 参考资料

- [AVSampleBufferDisplayLayer Documentation](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer)
- [Core Video Pixel Buffer Pool](https://developer.apple.com/documentation/corevideo/cvpixelbufferpool)
- [WWDC: Advances in AVKit](https://developer.apple.com/videos/play/wwdc2022/10147/)
