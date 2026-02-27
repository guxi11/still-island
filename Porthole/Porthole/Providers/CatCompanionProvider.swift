//
//  CatCompanionProvider.swift
//  Porthole
//
//  Provides an animated companion cat using GIF for PiP display.
//

import UIKit
import ImageIO

/// A content provider that displays an animated GIF cat in PiP window.
@MainActor
final class CatCompanionProvider: PiPContentProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "cat"
    static let displayName: String = "小猫陪伴"
    static let iconName: String = "cat.fill"
    
    /// 用于卡片预览的静态图（GIF第一帧）
    static var previewImage: UIImage? {
        guard let asset = NSDataAsset(name: "cat1"),
              let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - PiPContentProvider

    let contentView: UIView
    let preferredFrameRate: Int = 15

    // MARK: - Private Properties

    private let imageView: UIImageView
    private var gifFrames: [UIImage] = []
    private var frameDuration: TimeInterval = 0.1
    private var displayLink: CADisplayLink?
    private var currentFrameIndex: Int = 0
    private var lastFrameTime: CFTimeInterval = 0

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
        
        loadGifFrames()
        
        print("[CatCompanionProvider] Initialized with GIF animation, \(gifFrames.count) frames")
    }

    // MARK: - Private Methods
    
    private func loadGifFrames() {
        guard let asset = NSDataAsset(name: "cat1") else {
            print("[CatCompanionProvider] Failed to load cat1 data asset")
            return
        }
        
        guard let source = CGImageSourceCreateWithData(asset.data as CFData, nil) else {
            print("[CatCompanionProvider] Failed to create image source")
            return
        }
        
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return }
        
        var frames: [UIImage] = []
        var totalDuration: TimeInterval = 0
        
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            
            // 获取帧延迟
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                let delay = (gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifProps[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                totalDuration += delay
            }
        }
        
        gifFrames = frames
        frameDuration = frameCount > 0 ? totalDuration / Double(frameCount) : 0.1
        
        // 设置第一帧
        if let first = frames.first {
            imageView.image = first
        }
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[CatCompanionProvider] start()")
        
        guard !gifFrames.isEmpty else { return }
        
        currentFrameIndex = 0
        lastFrameTime = 0
        
        // 使用CADisplayLink驱动动画
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        print("[CatCompanionProvider] stop()")
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateFrame(_ link: CADisplayLink) {
        guard !gifFrames.isEmpty else { return }
        
        if lastFrameTime == 0 {
            lastFrameTime = link.timestamp
        }
        
        let elapsed = link.timestamp - lastFrameTime
        if elapsed >= frameDuration {
            currentFrameIndex = (currentFrameIndex + 1) % gifFrames.count
            imageView.image = gifFrames[currentFrameIndex]
            lastFrameTime = link.timestamp
        }
    }
}
