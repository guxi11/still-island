//
//  CatCompanionProvider.swift
//  Porthole
//
//  Provides an animated companion cat using GIF for PiP display.
//

import UIKit
import ImageIO

/// A content provider that displays an animated GIF cat in PiP window.
/// 优化：延迟加载GIF帧，减少内存占用
@MainActor
final class CatCompanionProvider: PiPContentProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "cat"
    static let displayName: String = "小猫陪伴"
    static let iconName: String = "cat.fill"
    
    /// 用于卡片预览的静态图（GIF第一帧）- 使用缓存避免重复加载
    private static var _previewImage: UIImage?
    static var previewImage: UIImage? {
        if let cached = _previewImage { return cached }
        guard let asset = NSDataAsset(name: "cat1"),
              let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        _previewImage = UIImage(cgImage: cgImage)
        return _previewImage
    }

    // MARK: - PiPContentProvider

    let contentView: UIView
    let preferredFrameRate: Int = 15

    // MARK: - Private Properties

    private let imageView: UIImageView
    
    // GIF源 - 延迟加载帧
    private var imageSource: CGImageSource?
    private var frameCount: Int = 0
    private var frameDurations: [TimeInterval] = []
    
    // 帧缓存 - 只缓存当前需要的帧
    private var frameCache: [Int: UIImage] = [:]
    private let maxCachedFrames = 5  // 最多缓存5帧
    
    private var displayLink: CADisplayLink?
    private var currentFrameIndex: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var accumulatedTime: CFTimeInterval = 0

    // MARK: - Initialization

    init() {
        let containerSize = CGSize(width: 200, height: 100)
        
        // 纯黑色背景容器
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = .black
        
        // 居中显示GIF的ImageView
        imageView = UIImageView(frame: container.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        container.addSubview(imageView)
        
        self.contentView = container
        
        // 只加载元数据，不加载所有帧
        loadGifMetadata()
        
        print("[CatCompanionProvider] Initialized with lazy-loaded GIF, \(frameCount) frames")
    }

    // MARK: - Private Methods
    
    /// 只加载GIF元数据（帧数和每帧时长），不加载实际图片数据
    private func loadGifMetadata() {
        guard let asset = NSDataAsset(name: "cat1") else {
            print("[CatCompanionProvider] Failed to load cat1 data asset")
            return
        }
        
        guard let source = CGImageSourceCreateWithData(asset.data as CFData, nil) else {
            print("[CatCompanionProvider] Failed to create image source")
            return
        }
        
        imageSource = source
        frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return }
        
        // 只读取帧时长信息
        var durations: [TimeInterval] = []
        for i in 0..<frameCount {
            var delay: TimeInterval = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                delay = (gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifProps[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                if delay < 0.02 {
                    delay = 0.1
                }
            }
            durations.append(delay)
        }
        frameDurations = durations
        
        // 预加载第一帧
        if let firstFrame = loadFrame(at: 0) {
            imageView.image = firstFrame
        }
    }
    
    /// 按需加载单帧
    private func loadFrame(at index: Int) -> UIImage? {
        // 检查缓存
        if let cached = frameCache[index] {
            return cached
        }
        
        // 从源加载
        guard let source = imageSource,
              let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            return nil
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // 添加到缓存，并清理旧缓存
        frameCache[index] = image
        cleanFrameCache(currentIndex: index)
        
        return image
    }
    
    /// 清理帧缓存，只保留当前帧附近的帧
    private func cleanFrameCache(currentIndex: Int) {
        guard frameCache.count > maxCachedFrames else { return }
        
        // 计算应该保留的帧索引范围
        let keepRange = Set((currentIndex - 2)...(currentIndex + 2)).map { 
            ($0 + frameCount) % frameCount 
        }
        
        // 移除不在范围内的帧
        frameCache = frameCache.filter { keepRange.contains($0.key) }
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[CatCompanionProvider] start()")
        
        guard frameCount > 0 else { return }
        
        currentFrameIndex = 0
        lastFrameTime = 0
        accumulatedTime = 0
        
        // 预加载前几帧
        for i in 0..<min(3, frameCount) {
            _ = loadFrame(at: i)
        }
        
        // 计算GIF的实际帧率
        let totalDuration = frameDurations.reduce(0, +)
        let avgFrameDuration = totalDuration / Double(frameDurations.count)
        let targetFPS = min(30, max(1, Int(1.0 / avgFrameDuration)))
        
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(targetFPS),
                maximum: Float(targetFPS),
                preferred: Float(targetFPS)
            )
        } else {
            displayLink?.preferredFramesPerSecond = targetFPS
        }
        
        displayLink?.add(to: .main, forMode: .common)
        print("[CatCompanionProvider] DisplayLink configured at \(targetFPS) fps")
    }

    func stop() {
        print("[CatCompanionProvider] stop()")
        displayLink?.invalidate()
        displayLink = nil
        
        // 清空帧缓存释放内存
        frameCache.removeAll()
    }
    
    @objc private func updateFrame(_ link: CADisplayLink) {
        guard frameCount > 0, !frameDurations.isEmpty else { return }
        
        if lastFrameTime == 0 {
            lastFrameTime = link.timestamp
            return
        }
        
        let elapsed = link.timestamp - lastFrameTime
        lastFrameTime = link.timestamp
        accumulatedTime += elapsed
        
        let currentFrameDuration = frameDurations[currentFrameIndex]
        if accumulatedTime >= currentFrameDuration {
            accumulatedTime -= currentFrameDuration
            currentFrameIndex = (currentFrameIndex + 1) % frameCount
            
            // 按需加载当前帧
            if let frame = loadFrame(at: currentFrameIndex) {
                imageView.image = frame
            }
            
            // 预加载下一帧（在后台线程）
            let nextIndex = (currentFrameIndex + 1) % frameCount
            Task.detached(priority: .utility) { [weak self] in
                await MainActor.run {
                    _ = self?.loadFrame(at: nextIndex)
                }
            }
        }
    }
}
