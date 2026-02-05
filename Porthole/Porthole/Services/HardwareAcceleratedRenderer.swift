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

/// Uses AVPlayer with AVPlayerItemVideoOutput for hardware-decoded video frames
final class VideoHardwareRenderer: HardwareAcceleratedRenderer {
    
    let displayLayer: AVSampleBufferDisplayLayer
    private let videoURL: URL
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var loopObserver: NSObjectProtocol?
    private var frameCount = 0
    private var videoRotationAngle: CGFloat = 0  // 视频旋转角度（弧度）
    
    init(videoURL: URL, displayLayer: AVSampleBufferDisplayLayer) {
        self.videoURL = videoURL
        self.displayLayer = displayLayer
        setupDisplayLayer()
        loadVideoTransform()
    }
    
    /// 加载视频的旋转变换信息
    private func loadVideoTransform() {
        let asset = AVAsset(url: videoURL)
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let transform = try await track.load(.preferredTransform)
                    
                    // 从 transform 矩阵计算旋转角度
                    // transform.a = cos(θ), transform.b = sin(θ)
                    let angle = atan2(transform.b, transform.a)
                    
                    await MainActor.run {
                        self.videoRotationAngle = angle
                        // 应用旋转到 display layer
                        if angle != 0 {
                            self.displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
                            print("[VideoHardwareRenderer] Applied rotation: \(angle * 180 / .pi) degrees")
                        }
                    }
                }
            } catch {
                print("[VideoHardwareRenderer] Failed to load video transform: \(error)")
            }
        }
    }
    
    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspectFill
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
    
    func start() {
        // Create player item
        let asset = AVAsset(url: videoURL)
        playerItem = AVPlayerItem(asset: asset)
        
        // Configure video output - don't restrict dimensions, let AVFoundation handle it
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem?.add(videoOutput!)
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
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
        
        // Start display link at 15fps
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFramesPerSecond = 15
        displayLink?.add(to: .main, forMode: .common)
        
        player?.play()
        print("[VideoHardwareRenderer] Started")
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
        guard let videoOutput = videoOutput,
              let playerItem = playerItem else { return }
        
        let currentTime = playerItem.currentTime()
        
        // Check if new frame is available
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return
        }
        
        // Create sample buffer using host time (critical for AVSampleBufferDisplayLayer)
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else {
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
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let formatDesc = formatDesc else { return nil }
        
        // Use host time for presentation timestamp - this is critical
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

/// Uses AVCaptureVideoDataOutput for direct pixel buffer access (no preview layer conversion)
final class CameraHardwareRenderer: NSObject, HardwareAcceleratedRenderer, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let displayLayer: AVSampleBufferDisplayLayer
    private var captureSession: AVCaptureSession?
    private let outputQueue = DispatchQueue(label: "com.porthole.camera.output", qos: .userInitiated)
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init()
        setupDisplayLayer()
    }
    
    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspectFill
        
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
        let session = AVCaptureSession()
        // Use low preset for better performance (480p)
        session.sessionPreset = .low
        
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
            print("[CameraHardwareRenderer] Camera configured: 15fps, low preset")
        } catch {
            print("[CameraHardwareRenderer] Failed to configure camera frame rate: \(error)")
        }
        
        session.addInput(input)
        
        // Add video data output for direct pixel buffer access
        let videoOutput = AVCaptureVideoDataOutput()
        // Reduce resolution by setting max dimensions
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 480,
            kCVPixelBufferHeightKey as String: 360
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            // Set video orientation
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
        
        captureSession = session
        
        outputQueue.async {
            session.startRunning()
            print("[CameraHardwareRenderer] Started with direct pixel buffer output")
        }
    }
    
    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Enqueue sample buffer directly to display layer
        displayLayer.enqueue(sampleBuffer)
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
