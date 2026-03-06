//
//  VideoFrameCodec.swift
//  Porthole
//
//  Efficient video frame encoding/decoding for network transmission.
//  Uses JPEG compression to reduce bandwidth while maintaining acceptable quality.
//

import Foundation
import UIKit
import AVFoundation
import CoreMedia
import CoreImage
import Accelerate

// MARK: - Video Frame Encoder

/// Encodes CMSampleBuffer to compressed data for network transmission
final class VideoFrameEncoder {
    
    // Fixed output size for transmission (smaller than PiP output for bandwidth)
    private static let outputWidth: Int = 200
    private static let outputHeight: Int = 100
    
    // JPEG compression quality (0.0 - 1.0)
    private var compressionQuality: CGFloat = 0.5
    
    // Pixel buffer pool for resizing
    private var pixelBufferPool: CVPixelBufferPool?
    private let ciContext: CIContext
    
    // Cached resize parameters
    private var cachedCropRect: CGRect?
    private var cachedScaleTransform: CGAffineTransform?
    private var lastSourceSize: CGSize = .zero
    
    init() {
        // Create GPU-accelerated CIContext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: true
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        
        setupPixelBufferPool()
    }
    
    private func setupPixelBufferPool() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.outputWidth,
            kCVPixelBufferHeightKey as String: Self.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
    }
    
    /// Set compression quality (0.0 - 1.0, default 0.5)
    func setCompressionQuality(_ quality: CGFloat) {
        compressionQuality = max(0.1, min(1.0, quality))
    }
    
    /// Encode a sample buffer to compressed data
    func encode(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        // Resize to transmission size
        guard let resizedBuffer = resizePixelBuffer(sourceBuffer) else {
            return nil
        }
        
        // Convert to JPEG
        guard let jpegData = compressToJPEG(resizedBuffer) else {
            return nil
        }
        
        // Create packet with dimensions
        var packetData = Data()
        let width = UInt16(Self.outputWidth)
        let height = UInt16(Self.outputHeight)
        withUnsafeBytes(of: width) { packetData.append(contentsOf: $0) }
        withUnsafeBytes(of: height) { packetData.append(contentsOf: $0) }
        packetData.append(jpegData)
        
        return packetData
    }
    
    private func resizePixelBuffer(_ sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
        
        // Create CIImage from source
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        // Get source size
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(sourceBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(sourceBuffer))
        let currentSourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        
        // Recalculate transforms if source size changed
        if currentSourceSize != lastSourceSize {
            lastSourceSize = currentSourceSize
            cachedCropRect = nil
            cachedScaleTransform = nil
            
            // Calculate cover crop
            let targetAspect = CGFloat(Self.outputWidth) / CGFloat(Self.outputHeight)
            let imageAspect = sourceWidth / sourceHeight
            
            if imageAspect > targetAspect {
                let cropWidth = sourceHeight * targetAspect
                let cropX = (sourceWidth - cropWidth) / 2
                cachedCropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: sourceHeight)
            } else {
                let cropHeight = sourceWidth / targetAspect
                let cropY = (sourceHeight - cropHeight) / 2
                cachedCropRect = CGRect(x: 0, y: cropY, width: sourceWidth, height: cropHeight)
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
        
        // Calculate scale transform
        if cachedScaleTransform == nil {
            let scaleX = CGFloat(Self.outputWidth) / croppedImage.extent.width
            let scaleY = CGFloat(Self.outputHeight) / croppedImage.extent.height
            cachedScaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
        
        // Apply scale
        let scaledImage = croppedImage.transformed(by: cachedScaleTransform!)
        
        // Render to output buffer
        ciContext.render(scaledImage, to: output)
        
        return output
    }
    
    private func compressToJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        // Create CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Create CGImage
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        // Convert to UIImage and compress
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: compressionQuality)
    }
}

// MARK: - Video Frame Decoder

/// Decodes compressed data back to CMSampleBuffer for display
final class VideoFrameDecoder {
    
    // Pixel buffer pool for decoded frames
    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?
    private var lastSize: CGSize = .zero
    
    private let ciContext: CIContext
    
    init() {
        // Create GPU-accelerated CIContext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    /// Decode compressed data to CMSampleBuffer
    func decode(_ data: Data) -> CMSampleBuffer? {
        // Parse packet header
        guard data.count >= 4 else { return nil }
        
        let width = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt16.self)
        }
        let height = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 2, as: UInt16.self)
        }
        
        // Extract JPEG data
        let jpegData = data.subdata(in: 4..<data.count)
        
        // Decompress JPEG
        guard let uiImage = UIImage(data: jpegData),
              let cgImage = uiImage.cgImage else {
            return nil
        }
        
        // Setup pixel buffer pool if size changed
        let currentSize = CGSize(width: Int(width), height: Int(height))
        if currentSize != lastSize {
            lastSize = currentSize
            setupPixelBufferPool(width: Int(width), height: Int(height))
        }
        
        // Create pixel buffer from CGImage
        guard let pixelBuffer = createPixelBuffer(from: cgImage, width: Int(width), height: Int(height)) else {
            return nil
        }
        
        // Create sample buffer
        return createSampleBuffer(from: pixelBuffer)
    }
    
    private func setupPixelBufferPool(width: Int, height: Int) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
        
        // Create format description
        if let pool = pixelBufferPool {
            var tempBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &tempBuffer)
            if let buffer = tempBuffer {
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
    }
    
    private func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        
        // Draw CGImage to context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        
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

// MARK: - Shared Camera Frame Compositor

/// Composites local and remote camera frames into a single output
final class SharedCameraCompositor {
    
    // Output size (same as PiP output)
    private static let outputWidth: Int = 400
    private static let outputHeight: Int = 200
    
    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?
    private let ciContext: CIContext
    
    // Current display mode
    var displayMode: SharedDisplayMode = .sideBySide
    
    init() {
        // Create GPU-accelerated CIContext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        
        setupPixelBufferPool()
    }
    
    private func setupPixelBufferPool() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.outputWidth,
            kCVPixelBufferHeightKey as String: Self.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
        
        // Create format description
        if let pool = pixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            if let buffer = pixelBuffer {
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
    }
    
    /// Composite local and remote frames based on display mode
    func composite(local: CVPixelBuffer?, remote: CVPixelBuffer?) -> CMSampleBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
        
        // Determine which frames to use based on mode
        switch displayMode {
        case .local:
            guard let localBuffer = local else { return nil }
            return compositeSingleFrame(localBuffer, to: output)
            
        case .remote:
            guard let remoteBuffer = remote else { return nil }
            return compositeSingleFrame(remoteBuffer, to: output)
            
        case .sideBySide:
            return compositeSideBySide(local: local, remote: remote, to: output)
            
        case .pictureInPicture:
            return compositePictureInPicture(local: local, remote: remote, to: output)
        }
    }
    
    private func compositeSingleFrame(_ source: CVPixelBuffer, to output: CVPixelBuffer) -> CMSampleBuffer? {
        let ciImage = CIImage(cvPixelBuffer: source)
        
        // Scale to fill output
        let scaleX = CGFloat(Self.outputWidth) / ciImage.extent.width
        let scaleY = CGFloat(Self.outputHeight) / ciImage.extent.height
        let scale = max(scaleX, scaleY)
        
        var scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Center crop
        let cropX = (scaledImage.extent.width - CGFloat(Self.outputWidth)) / 2
        let cropY = (scaledImage.extent.height - CGFloat(Self.outputHeight)) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: CGFloat(Self.outputWidth), height: CGFloat(Self.outputHeight))
        scaledImage = scaledImage.cropped(to: cropRect)
        
        // Translate to origin
        scaledImage = scaledImage.transformed(by: CGAffineTransform(
            translationX: -scaledImage.extent.origin.x,
            y: -scaledImage.extent.origin.y
        ))
        
        ciContext.render(scaledImage, to: output)
        return createSampleBuffer(from: output)
    }
    
    private func compositeSideBySide(local: CVPixelBuffer?, remote: CVPixelBuffer?, to output: CVPixelBuffer) -> CMSampleBuffer? {
        // Clear output with black
        CVPixelBufferLockBaseAddress(output, [])
        let baseAddress = CVPixelBufferGetBaseAddress(output)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
        memset(baseAddress, 0, bytesPerRow * Self.outputHeight)
        CVPixelBufferUnlockBaseAddress(output, [])
        
        // Each side is half width
        let halfWidth = Self.outputWidth / 2
        
        // Draw local on left
        if let localBuffer = local {
            let localImage = CIImage(cvPixelBuffer: localBuffer)
            let scaledLocal = scaleAndCrop(localImage, toWidth: halfWidth, height: Self.outputHeight)
            
            var outputImage = CIImage(cvPixelBuffer: output)
            outputImage = scaledLocal.composited(over: outputImage)
            ciContext.render(outputImage, to: output)
        }
        
        // Draw remote on right
        if let remoteBuffer = remote {
            let remoteImage = CIImage(cvPixelBuffer: remoteBuffer)
            var scaledRemote = scaleAndCrop(remoteImage, toWidth: halfWidth, height: Self.outputHeight)
            
            // Translate to right half
            scaledRemote = scaledRemote.transformed(by: CGAffineTransform(translationX: CGFloat(halfWidth), y: 0))
            
            var outputImage = CIImage(cvPixelBuffer: output)
            outputImage = scaledRemote.composited(over: outputImage)
            ciContext.render(outputImage, to: output)
        }
        
        return createSampleBuffer(from: output)
    }
    
    private func compositePictureInPicture(local: CVPixelBuffer?, remote: CVPixelBuffer?, to output: CVPixelBuffer) -> CMSampleBuffer? {
        // Local is main view, remote is small overlay in corner
        guard let localBuffer = local else {
            // If no local, just show remote
            if let remoteBuffer = remote {
                return compositeSingleFrame(remoteBuffer, to: output)
            }
            return nil
        }
        
        // Draw local as background
        let localImage = CIImage(cvPixelBuffer: localBuffer)
        let scaledLocal = scaleAndCrop(localImage, toWidth: Self.outputWidth, height: Self.outputHeight)
        ciContext.render(scaledLocal, to: output)
        
        // Draw remote as small overlay in top-right corner
        if let remoteBuffer = remote {
            let remoteImage = CIImage(cvPixelBuffer: remoteBuffer)
            let pipWidth = Self.outputWidth / 4  // 25% width
            let pipHeight = Self.outputHeight / 4
            var scaledRemote = scaleAndCrop(remoteImage, toWidth: pipWidth, height: pipHeight)
            
            // Position in top-right corner with padding
            let padding: CGFloat = 8
            let xOffset = CGFloat(Self.outputWidth - pipWidth) - padding
            let yOffset = CGFloat(Self.outputHeight - pipHeight) - padding
            scaledRemote = scaledRemote.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
            
            var outputImage = CIImage(cvPixelBuffer: output)
            outputImage = scaledRemote.composited(over: outputImage)
            ciContext.render(outputImage, to: output)
        }
        
        return createSampleBuffer(from: output)
    }
    
    private func scaleAndCrop(_ image: CIImage, toWidth width: Int, height: Int) -> CIImage {
        let targetAspect = CGFloat(width) / CGFloat(height)
        let imageAspect = image.extent.width / image.extent.height
        
        var processed = image
        
        // Crop to aspect ratio
        if imageAspect > targetAspect {
            let cropWidth = image.extent.height * targetAspect
            let cropX = (image.extent.width - cropWidth) / 2
            processed = image.cropped(to: CGRect(x: cropX, y: 0, width: cropWidth, height: image.extent.height))
        } else {
            let cropHeight = image.extent.width / targetAspect
            let cropY = (image.extent.height - cropHeight) / 2
            processed = image.cropped(to: CGRect(x: 0, y: cropY, width: image.extent.width, height: cropHeight))
        }
        
        // Translate to origin
        processed = processed.transformed(by: CGAffineTransform(
            translationX: -processed.extent.origin.x,
            y: -processed.extent.origin.y
        ))
        
        // Scale to target size
        let scaleX = CGFloat(width) / processed.extent.width
        let scaleY = CGFloat(height) / processed.extent.height
        processed = processed.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        return processed
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        
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
