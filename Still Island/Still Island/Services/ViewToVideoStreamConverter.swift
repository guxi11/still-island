//
//  ViewToVideoStreamConverter.swift
//  Still Island
//
//  Converts UIView content to video stream for PiP display.
//

import UIKit
import AVFoundation
import CoreMedia

/// Converts a UIView's rendered content into a video stream suitable for PiP display.
/// Uses CADisplayLink for frame timing and AVSampleBufferDisplayLayer for video output.
final class ViewToVideoStreamConverter {
    
    // MARK: - Public Properties
    
    /// The display layer that receives video frames. Can be set externally or use internal one.
    private(set) var displayLayer: AVSampleBufferDisplayLayer
    
    /// Whether the converter is currently capturing frames.
    private(set) var isCapturing = false
    
    // MARK: - Private Properties
    
    private var contentView: UIView?
    private var displayLink: CADisplayLink?
    private var targetFrameRate: Int = 10
    private var lastFrameTime: CFTimeInterval = 0
    private var frameInterval: CFTimeInterval = 0.1 // 10 FPS default
    
    // Pixel buffer pool for efficient buffer reuse
    private var pixelBufferPool: CVPixelBufferPool?
    private var currentSize: CGSize = .zero
    
    // Format description for sample buffers
    private var formatDescription: CMVideoFormatDescription?
    
    // Frame counter for debugging
    private var frameCount: Int = 0
    
    // Store timebase reference
    private var controlTimebase: CMTimebase?
    
    // MARK: - Initialization
    
    init() {
        displayLayer = AVSampleBufferDisplayLayer()
        setupDisplayLayer(displayLayer)
    }
    
    /// Initialize with an external display layer (e.g., from a view's layerClass)
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        setupDisplayLayer(displayLayer)
    }
    
    private func setupDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        
        // Set up control timebase - required for PiP
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase = timebase {
            // Set initial time to current host time
            let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
            CMTimebaseSetTime(timebase, time: hostTime)
            CMTimebaseSetRate(timebase, rate: 1.0)
            layer.controlTimebase = timebase
            self.controlTimebase = timebase
            print("[Converter] Control timebase configured with time: \(CMTimeGetSeconds(hostTime))")
        }
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Methods
    
    /// Updates the display layer (used when switching to a view-backed layer)
    func setDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        // Stop current capture
        let wasCapturing = isCapturing
        let previousFrameRate = targetFrameRate
        stopCapture()
        
        // Set new layer and configure it
        displayLayer = layer
        setupDisplayLayer(layer)
        
        // Restart if was capturing
        if wasCapturing {
            startCapture(frameRate: previousFrameRate)
        }
    }
    
    /// Sets the content view to be captured.
    /// - Parameter view: The UIView whose content will be converted to video frames.
    func setContentView(_ view: UIView) {
        contentView = view
        
        // Update buffer pool if size changed
        let size = view.bounds.size
        if size != currentSize && size.width > 0 && size.height > 0 {
            currentSize = size
            setupPixelBufferPool(for: size)
            print("[Converter] Content view set with size: \(size)")
        }
    }
    
    /// Starts capturing frames at the specified frame rate.
    /// - Parameter frameRate: Target frames per second (1-60). Default is 10 FPS.
    func startCapture(frameRate: Int = 10) {
        guard !isCapturing else { return }
        
        targetFrameRate = max(1, min(60, frameRate))
        frameInterval = 1.0 / Double(targetFrameRate)
        lastFrameTime = 0
        frameCount = 0
        
        // Flush the layer before starting to ensure clean state
        displayLayer.flush()
        
        // Request media data callback to know when layer is ready
        displayLayer.requestMediaDataWhenReady(on: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if self.frameCount == 0 {
                print("[Converter] DisplayLayer is now ready for media data")
            }
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
        
        isCapturing = true
        print("[Converter] Started capture at \(targetFrameRate) FPS")
    }
    
    /// Stops capturing frames and releases resources.
    func stopCapture() {
        displayLink?.invalidate()
        displayLink = nil
        displayLayer.stopRequestingMediaData()
        isCapturing = false
    }
    
    // MARK: - Private Methods
    
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        // Frame rate limiting
        let currentTime = link.timestamp
        guard currentTime - lastFrameTime >= frameInterval else { return }
        lastFrameTime = currentTime
        
        // Capture and push frame
        captureAndPushFrame()
    }
    
    private func captureAndPushFrame() {
        guard let view = contentView else {
            return
        }
        
        let size = view.bounds.size
        guard size.width > 0 && size.height > 0 else {
            return
        }
        
        // Update pool if size changed
        if size != currentSize {
            currentSize = size
            setupPixelBufferPool(for: size)
        }
        
        // Force layout before rendering
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Create pixel buffer from view using UIGraphicsImageRenderer
        guard let pixelBuffer = createPixelBufferUsingRenderer(from: view) else {
            if frameCount < 5 {
                print("[Converter] Failed to create pixel buffer")
            }
            return
        }
        
        // Create sample buffer
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else {
            if frameCount < 5 {
                print("[Converter] Failed to create sample buffer")
            }
            return
        }
        
        // Push to display layer
        if displayLayer.status == .failed {
            print("[Converter] DisplayLayer failed, flushing...")
            displayLayer.flush()
            return
        }
        
        // Just push frames - the layer will handle buffering
        displayLayer.enqueue(sampleBuffer)
        
        frameCount += 1
        if frameCount == 1 || frameCount % 30 == 0 {
            print("[Converter] Frame \(frameCount) pushed, layer status: \(displayLayer.status.rawValue)")
        }
    }
    
    private func setupPixelBufferPool(for size: CGSize) {
        let scale = UIScreen.main.scale
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        
        print("[Converter] Setting up pixel buffer pool: \(width)x\(height)")
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        // Release old pool
        pixelBufferPool = nil
        formatDescription = nil
        
        // Create new pool
        let poolStatus = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
        if poolStatus != kCVReturnSuccess {
            print("[Converter] Failed to create pixel buffer pool: \(poolStatus)")
            return
        }
        
        // Create format description
        var pixelBuffer: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            if let buffer = pixelBuffer {
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &formatDescription
                )
                print("[Converter] Format description created")
            }
        }
    }
    
    private func createPixelBufferUsingRenderer(from view: UIView) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else {
            return nil
        }
        
        // Render view to image
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        // Draw image to pixel buffer
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        
        var sampleBuffer: CMSampleBuffer?
        // Use host time for presentation timestamp to match timebase
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(targetFrameRate)),
            presentationTimeStamp: hostTime,
            decodeTimeStamp: .invalid
        )
        
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard status == noErr else { return nil }
        
        return sampleBuffer
    }
}
