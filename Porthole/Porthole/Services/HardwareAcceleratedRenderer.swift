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
    
    init(videoURL: URL, displayLayer: AVSampleBufferDisplayLayer) {
        self.videoURL = videoURL
        self.displayLayer = displayLayer
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
        // Create player item with video output
        let asset = AVAsset(url: videoURL)
        playerItem = AVPlayerItem(asset: asset)
        
        // Configure video output for pixel buffer access
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem?.add(videoOutput!)
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.actionAtItemEnd = .none // Handle looping manually
        
        // Setup looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
        
        // Start display link to copy frames
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
        
        player?.play()
        print("[VideoHardwareRenderer] Started with hardware decoder")
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
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
        
        // Create sample buffer from hardware-decoded pixel buffer
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer, presentationTime: currentTime) else {
            return
        }
        
        displayLayer.enqueue(sampleBuffer)
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let formatDesc = formatDesc else { return nil }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
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
        session.sessionPreset = .medium // Balance quality/performance
        
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
        
        session.addInput(input)
        
        // Add video data output for direct pixel buffer access
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
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
        // Sample buffer is already hardware-ready, just enqueue directly
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
