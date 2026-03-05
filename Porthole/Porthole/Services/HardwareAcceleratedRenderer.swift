//
//  HardwareAcceleratedRenderer.swift
//  Porthole
//
//  Optimized rendering for PiP using hardware acceleration:
//  - AVPlayer for video (hardware decoder)
//  - AVCaptureVideoDataOutput for camera (direct pixel buffers)
//  - Metal for UIView content (GPU rendering)
//

import UIKit
import AVFoundation
import CoreMedia
import Metal
import MetalKit

// MARK: - Base Protocol

/// Renders content to AVSampleBufferDisplayLayer with hardware acceleration
protocol HardwareAcceleratedRenderer: AnyObject {
    var displayLayer: AVSampleBufferDisplayLayer { get }
    func start()
    func stop()
}

// MARK: - Video Hardware Renderer

/// Uses AVPlayer with AVPlayerItemVideoOutput for hardware-decoded video frames.
/// Outputs fixed-size frames (2:1 aspect ratio) with cover-style cropping.
/// Video is played muted by default.
final class VideoHardwareRenderer: HardwareAcceleratedRenderer {
    
    // Fixed output size for PiP (2:1 aspect ratio)
    private static let outputWidth: Int = 400
    private static let outputHeight: Int = 200
    
    let displayLayer: AVSampleBufferDisplayLayer
    private let videoURL: URL
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var loopObserver: NSObjectProtocol?
    private var frameCount = 0
    
    // Video transform info
    private var videoTransform: CGAffineTransform = .identity
    private var videoNaturalSize: CGSize = .zero
    
    // Pixel buffer pool for output
    private var outputPixelBufferPool: CVPixelBufferPool?
    private var outputFormatDescription: CMVideoFormatDescription?
    
    // Core Image context for efficient GPU processing
    private let ciContext: CIContext
    
    // 缓存的变换矩阵，避免每帧重复计算
    private var cachedRotationTransform: CGAffineTransform?
    private var cachedCropRect: CGRect?
    private var cachedScaleTransform: CGAffineTransform?
    private var lastSourceSize: CGSize = .zero
    
    // 帧率控制
    private var targetFrameRate: Int = 15
    private var lastFrameTime: CFTimeInterval = 0
    private var frameInterval: CFTimeInterval = 1.0 / 15.0
    
    init(videoURL: URL, displayLayer: AVSampleBufferDisplayLayer) {
        self.videoURL = videoURL
        self.displayLayer = displayLayer
        
        // 创建GPU加速的CIContext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,  // 不缓存中间结果，节省内存
                .priorityRequestLow: true    // 低优先级，避免影响主线程
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        
        setupDisplayLayer()
        setupOutputPixelBufferPool()
        loadVideoInfo()
    }
    
    /// 加载视频信息（旋转和尺寸）
    private func loadVideoInfo() {
        let asset = AVAsset(url: videoURL)
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let transform = try await track.load(.preferredTransform)
                    let naturalSize = try await track.load(.naturalSize)
                    
                    await MainActor.run {
                        self.videoTransform = transform
                        self.videoNaturalSize = naturalSize
                        
                        // 计算旋转角度用于日志
                        let angle = atan2(transform.b, transform.a)
                        print("[VideoHardwareRenderer] Video info: size=\(naturalSize), rotation=\(angle * 180 / .pi)°")
                    }
                }
            } catch {
                print("[VideoHardwareRenderer] Failed to load video info: \(error)")
            }
        }
    }
    
    private func setupDisplayLayer() {
        // Use resizeAspect since we're outputting pre-cropped frames
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase = timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1.0)
            displayLayer.controlTimebase = timebase
        }
    }
    
    private func setupOutputPixelBufferPool() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.outputWidth,
            kCVPixelBufferHeightKey as String: Self.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &outputPixelBufferPool)
        
        // Create format description
        if let pool = outputPixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            if let buffer = pixelBuffer {
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &outputFormatDescription
                )
            }
        }
    }
    
    func start() {
        // Create player item
        let asset = AVAsset(url: videoURL)
        playerItem = AVPlayerItem(asset: asset)
        
        // Configure video output
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem?.add(videoOutput!)
        
        // Create player and set to muted
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true  // 静音播放
        player?.actionAtItemEnd = .none
        
        // Setup looping
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero) { finished in
                if finished {
                    self?.player?.play()
                }
            }
        }
        
        // Start display link with frame rate control
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(targetFrameRate),
                maximum: Float(targetFrameRate),
                preferred: Float(targetFrameRate)
            )
        } else {
            displayLink?.preferredFramesPerSecond = targetFrameRate
        }
        displayLink?.add(to: .main, forMode: .common)
        
        player?.play()
        print("[VideoHardwareRenderer] Started (muted) with fixed output size: \(Self.outputWidth)x\(Self.outputHeight), \(targetFrameRate)fps")
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        player?.pause()
        player = nil
        playerItem = nil
        videoOutput = nil
    }
    
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        // 帧率限制
        let currentTime = link.timestamp
        guard currentTime - lastFrameTime >= frameInterval else { return }
        lastFrameTime = currentTime
        
        guard let videoOutput = videoOutput,
              let playerItem = playerItem else { return }
        
        let itemTime = playerItem.currentTime()
        
        // Check if new frame is available
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let sourcePixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return
        }
        
        // Process frame: apply rotation and cover-crop to fixed size
        guard let outputPixelBuffer = processFrame(sourcePixelBuffer) else {
            return
        }
        
        // Create sample buffer
        guard let sampleBuffer = createSampleBuffer(from: outputPixelBuffer) else {
            return
        }
        
        // Check layer status and flush if failed
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        
        displayLayer.enqueue(sampleBuffer)
        
        frameCount += 1
        if frameCount == 1 || frameCount % 60 == 0 {
            print("[VideoHardwareRenderer] Frame \(frameCount), layer status: \(displayLayer.status.rawValue)")
        }
    }
    
    /// 处理视频帧：应用旋转并裁剪到固定尺寸（优化版，缓存变换矩阵）
    private func processFrame(_ sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = outputPixelBufferPool else { return nil }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
        
        // Create CIImage from source
        var ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        // 获取源图像尺寸
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(sourceBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(sourceBuffer))
        let currentSourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        
        // 如果源尺寸变化，重新计算变换矩阵
        if currentSourceSize != lastSourceSize {
            lastSourceSize = currentSourceSize
            cachedRotationTransform = nil
            cachedCropRect = nil
            cachedScaleTransform = nil
        }
        
        // 应用视频的旋转变换
        if videoTransform != .identity {
            if cachedRotationTransform == nil {
                let angle = atan2(videoTransform.b, videoTransform.a)
                let normalizedAngle = angle < 0 ? angle + 2 * .pi : angle
                let degrees = Int(round(normalizedAngle * 180 / .pi))
                
                switch degrees {
                case 90:
                    cachedRotationTransform = CGAffineTransform(rotationAngle: -.pi / 2)
                case 180:
                    cachedRotationTransform = CGAffineTransform(rotationAngle: .pi)
                case 270:
                    cachedRotationTransform = CGAffineTransform(rotationAngle: .pi / 2)
                default:
                    cachedRotationTransform = .identity
                }
            }
            
            if let transform = cachedRotationTransform, transform != .identity {
                let rotatedImage = ciImage.transformed(by: transform)
                ciImage = rotatedImage.transformed(by: CGAffineTransform(
                    translationX: -rotatedImage.extent.origin.x,
                    y: -rotatedImage.extent.origin.y
                ))
            }
        }
        
        // 现在 ciImage 是正确方向的图像，获取其尺寸
        let imageExtent = ciImage.extent
        let imageWidth = imageExtent.width
        let imageHeight = imageExtent.height
        
        // 目标尺寸
        let targetWidth = CGFloat(Self.outputWidth)
        let targetHeight = CGFloat(Self.outputHeight)
        let targetAspect = targetWidth / targetHeight  // 2:1
        
        // 计算 cover 裁剪区域（缓存）
        if cachedCropRect == nil {
            let imageAspect = imageWidth / imageHeight
            
            if imageAspect > targetAspect {
                let cropWidth = imageHeight * targetAspect
                let cropX = (imageWidth - cropWidth) / 2
                cachedCropRect = CGRect(x: imageExtent.origin.x + cropX, y: imageExtent.origin.y, width: cropWidth, height: imageHeight)
            } else {
                let cropHeight = imageWidth / targetAspect
                let cropY = (imageHeight - cropHeight) / 2
                cachedCropRect = CGRect(x: imageExtent.origin.x, y: imageExtent.origin.y + cropY, width: imageWidth, height: cropHeight)
            }
        }
        
        // 裁剪
        guard let cropRect = cachedCropRect else { return nil }
        var croppedImage = ciImage.cropped(to: cropRect)
        
        // 移动到原点
        croppedImage = croppedImage.transformed(by: CGAffineTransform(
            translationX: -croppedImage.extent.origin.x,
            y: -croppedImage.extent.origin.y
        ))
        
        // 缩放到目标尺寸（缓存）
        if cachedScaleTransform == nil {
            let scaleX = targetWidth / croppedImage.extent.width
            let scaleY = targetHeight / croppedImage.extent.height
            cachedScaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
        
        let scaledImage = croppedImage.transformed(by: cachedScaleTransform!)
        
        // 渲染到输出 buffer
        ciContext.render(scaledImage, to: output)
        
        return output
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let formatDesc = outputFormatDescription else { return nil }
        
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: hostTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - Camera Hardware Renderer

/// Uses AVCaptureVideoDataOutput for direct pixel buffer access (no preview layer conversion).
/// Outputs fixed-size frames (2:1 aspect ratio) with cover-style cropping to match other providers.
final class CameraHardwareRenderer: NSObject, HardwareAcceleratedRenderer, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Fixed output size for PiP (2:1 aspect ratio, same as VideoHardwareRenderer)
    private static let outputWidth: Int = 400
    private static let outputHeight: Int = 200
    
    let displayLayer: AVSampleBufferDisplayLayer
    private var captureSession: AVCaptureSession?
    private let outputQueue = DispatchQueue(label: "com.porthole.camera.output", qos: .userInitiated)
    
    // Pixel buffer pool for output
    private var outputPixelBufferPool: CVPixelBufferPool?
    private var outputFormatDescription: CMVideoFormatDescription?
    
    // Core Image context for efficient GPU processing
    private let ciContext: CIContext
    
    // Cached transforms for performance
    private var cachedCropRect: CGRect?
    private var cachedScaleTransform: CGAffineTransform?
    private var lastSourceSize: CGSize = .zero
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        
        // Create GPU-accelerated CIContext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: true
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        
        super.init()
        setupDisplayLayer()
        setupOutputPixelBufferPool()
    }
    
    private func setupDisplayLayer() {
        // Use resizeAspect since we're outputting pre-cropped frames
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase = timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1.0)
            displayLayer.controlTimebase = timebase
        }
    }
    
    private func setupOutputPixelBufferPool() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.outputWidth,
            kCVPixelBufferHeightKey as String: Self.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &outputPixelBufferPool)
        
        // Create format description
        if let pool = outputPixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            if let buffer = pixelBuffer {
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &outputFormatDescription
                )
            }
        }
    }
    
    func start() {
        let session = AVCaptureSession()
        // Use medium preset for better quality (720p)
        session.sessionPreset = .medium
        
        // Enable multitasking for background operation
        if #available(iOS 16.0, *) {
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
            }
        }
        
        // Get back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            print("[CameraHardwareRenderer] Failed to setup camera")
            return
        }
        
        // Configure camera for lower frame rate (15fps)
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            camera.unlockForConfiguration()
            print("[CameraHardwareRenderer] Camera configured: 15fps, medium preset")
        } catch {
            print("[CameraHardwareRenderer] Failed to configure camera frame rate: \(error)")
        }
        
        session.addInput(input)
        
        // Add video data output for direct pixel buffer access
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            // Set video orientation to portrait (90 degrees)
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
        
        captureSession = session
        
        outputQueue.async {
            session.startRunning()
            print("[CameraHardwareRenderer] Started with fixed output size: \(Self.outputWidth)x\(Self.outputHeight)")
        }
    }
    
    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Process frame: cover-crop to fixed 2:1 size
        guard let outputPixelBuffer = processFrame(sourcePixelBuffer) else {
            return
        }
        
        // Create sample buffer with processed frame
        guard let outputSampleBuffer = createSampleBuffer(from: outputPixelBuffer) else {
            return
        }
        
        // Check layer status and flush if failed
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        
        displayLayer.enqueue(outputSampleBuffer)
    }
    
    /// Process camera frame: apply cover-style crop to fixed 2:1 aspect ratio
    private func processFrame(_ sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = outputPixelBufferPool else { return nil }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
        
        // Create CIImage from source
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        // Get source image size
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(sourceBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(sourceBuffer))
        let currentSourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        
        // Recalculate transforms if source size changed
        if currentSourceSize != lastSourceSize {
            lastSourceSize = currentSourceSize
            cachedCropRect = nil
            cachedScaleTransform = nil
        }
        
        // Target dimensions
        let targetWidth = CGFloat(Self.outputWidth)
        let targetHeight = CGFloat(Self.outputHeight)
        let targetAspect = targetWidth / targetHeight  // 2:1
        
        // Calculate cover crop region (cached)
        if cachedCropRect == nil {
            let imageExtent = ciImage.extent
            let imageWidth = imageExtent.width
            let imageHeight = imageExtent.height
            let imageAspect = imageWidth / imageHeight
            
            if imageAspect > targetAspect {
                // Source is wider - crop left and right
                let cropWidth = imageHeight * targetAspect
                let cropX = (imageWidth - cropWidth) / 2
                cachedCropRect = CGRect(x: imageExtent.origin.x + cropX, y: imageExtent.origin.y, width: cropWidth, height: imageHeight)
            } else {
                // Source is taller - crop top and bottom
                let cropHeight = imageWidth / targetAspect
                let cropY = (imageHeight - cropHeight) / 2
                cachedCropRect = CGRect(x: imageExtent.origin.x, y: imageExtent.origin.y + cropY, width: imageWidth, height: cropHeight)
            }
        }
        
        // Apply crop
        guard let cropRect = cachedCropRect else { return nil }
        var croppedImage = ciImage.cropped(to: cropRect)
        
        // Translate to origin
        croppedImage = croppedImage.transformed(by: CGAffineTransform(
            translationX: -croppedImage.extent.origin.x,
            y: -croppedImage.extent.origin.y
        ))
        
        // Calculate scale transform (cached)
        if cachedScaleTransform == nil {
            let scaleX = targetWidth / croppedImage.extent.width
            let scaleY = targetHeight / croppedImage.extent.height
            cachedScaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
        
        // Apply scale
        let scaledImage = croppedImage.transformed(by: cachedScaleTransform!)
        
        // Render to output buffer
        ciContext.render(scaledImage, to: output)
        
        return output
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let formatDesc = outputFormatDescription else { return nil }
        
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: hostTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - Metal UIView Renderer

/// Uses Metal to render UIView content to CVPixelBuffer (GPU-accelerated, avoids UIKit layout overhead)
final class MetalUIViewRenderer: NSObject, HardwareAcceleratedRenderer, MTKViewDelegate {
    
    let displayLayer: AVSampleBufferDisplayLayer
    private let sourceView: UIView // Original UIView content to render
    private let metalView: MTKView
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var formatDescription: CMVideoFormatDescription?
    private var frameCount: Int = 0
    
    init(sourceView: UIView, displayLayer: AVSampleBufferDisplayLayer) {
        self.sourceView = sourceView
        self.displayLayer = displayLayer
        
        // Create Metal view matching source size
        metalView = MTKView(frame: sourceView.bounds)
        
        super.init()
        
        setupMetal()
        setupDisplayLayer()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[MetalUIViewRenderer] Metal not supported")
            return
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        metalView.device = device
        metalView.delegate = self
        metalView.framebufferOnly = false // Allow texture access
        metalView.preferredFramesPerSecond = 10 // Match previous frame rate
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        
        // Create texture cache for CVPixelBuffer conversion
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        print("[MetalUIViewRenderer] Metal initialized")
    }
    
    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase = timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1.0)
            displayLayer.controlTimebase = timebase
        }
    }
    
    func start() {
        metalView.isPaused = false
        print("[MetalUIViewRenderer] Started")
    }
    
    func stop() {
        metalView.isPaused = true
    }
    
    // MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        formatDescription = nil
    }
    
    func draw(in view: MTKView) {
        guard let device = device,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable else {
            return
        }
        
        // Render sourceView to Metal texture
        let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
        let image = renderer.image { ctx in
            sourceView.layer.render(in: ctx.cgContext)
        }
        
        guard let cgImage = image.cgImage else { return }
        
        // Create texture from CGImage
        let textureLoader = MTKTextureLoader(device: device)
        guard let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ]) else {
            return
        }
        
        // Blit texture to drawable
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        
        blitEncoder.copy(from: texture, to: drawable.texture)
        blitEncoder.endEncoding()
        
        // Convert drawable to pixel buffer and sample buffer
        if let pixelBuffer = convertTextureToPixelBuffer(texture: drawable.texture) {
            if let sampleBuffer = createSampleBuffer(from: pixelBuffer) {
                displayLayer.enqueue(sampleBuffer)
                frameCount += 1
            }
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func convertTextureToPixelBuffer(texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }
        
        return buffer
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            )
        }
        
        guard let formatDesc = formatDescription else { return nil }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}
