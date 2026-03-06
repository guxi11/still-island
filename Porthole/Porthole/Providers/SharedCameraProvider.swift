//
//  SharedCameraProvider.swift
//  Porthole
//
//  Provides shared camera functionality with Multipeer Connectivity.
//  Supports local camera capture and remote video stream display.
//

import UIKit
import AVFoundation
import CoreMedia
import Combine

/// A content provider that displays shared camera feeds (local + remote) in PiP window.
/// Uses Multipeer Connectivity for real-time video sharing between devices.
@MainActor
final class SharedCameraProvider: NSObject, DirectVideoProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "sharedCamera"
    static let displayName: String = "实景共享"
    static let iconName: String = "person.2.wave.2.fill"
    
    // MARK: - PiPContentProvider Properties
    
    let contentView: UIView
    let preferredFrameRate: Int = 15  // Lower frame rate for network efficiency
    
    // MARK: - DirectVideoProvider
    
    private var outputLayer: AVSampleBufferDisplayLayer?
    
    // MARK: - Public Properties
    
    /// The Multipeer service instance (shared with UI)
    let multipeerService = MultipeerService()
    
    /// Current display mode
    @Published var displayMode: SharedDisplayMode = .sideBySide {
        didSet {
            compositor?.displayMode = displayMode
        }
    }
    
    /// Whether local camera is currently sharing
    @Published private(set) var isSharing = false
    
    // MARK: - Private Properties
    
    private var cameraRenderer: SharedCameraRenderer?
    private var compositor: SharedCameraCompositor?
    private var displayLink: CADisplayLink?
    
    private let placeholderLabel: UILabel
    private var isRunning = false
    
    // Remote frame buffer
    private var latestRemoteFrame: CVPixelBuffer?
    private var latestLocalFrame: CVPixelBuffer?
    private let frameLock = NSLock()
    
    // Frame timing
    private var lastOutputTime: CFTimeInterval = 0
    private let outputFrameInterval: CFTimeInterval = 1.0 / 15.0
    
    // App lifecycle
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    override init() {
        // Create container view
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black
        container.clipsToBounds = true
        
        // Create placeholder label
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.text = "等待连接..."
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        // Center the label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])
        
        self.contentView = container
        self.placeholderLabel = label
        
        super.init()
        
        // Setup multipeer delegate
        multipeerService.delegate = self
        
        print("[SharedCameraProvider] Initialized")
    }
    
    deinit {
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - DirectVideoProvider Methods
    
    func setOutputLayer(_ layer: AVSampleBufferDisplayLayer) {
        print("[SharedCameraProvider] setOutputLayer called")
        self.outputLayer = layer
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[SharedCameraProvider] start()")
        
        guard !isRunning else { return }
        isRunning = true
        
        // Setup audio session
        configureAudioSession()
        
        // Create compositor
        compositor = SharedCameraCompositor()
        compositor?.displayMode = displayMode
        
        // Setup camera if authorized
        setupCameraIfAuthorized()
        
        // Setup display link for compositing output
        setupDisplayLink()
        
        // Setup app lifecycle handling
        setupAppLifecycleHandling()
        
        // Update placeholder
        updatePlaceholder()
    }
    
    func stop() {
        print("[SharedCameraProvider] stop()")
        
        isRunning = false
        
        // Stop display link
        displayLink?.invalidate()
        displayLink = nil
        
        // Stop camera
        cameraRenderer?.stop()
        cameraRenderer = nil
        
        // Leave room
        if multipeerService.state.isActive {
            multipeerService.leaveRoom()
        }
        
        // Clear frames
        frameLock.lock()
        latestLocalFrame = nil
        latestRemoteFrame = nil
        frameLock.unlock()
        
        // Remove lifecycle observer
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }
        
        isSharing = false
    }
    
    // MARK: - Room Management
    
    /// Create a new room and start sharing
    func createRoom(name: String) {
        multipeerService.createRoom(name: name)
        startSharing()
    }
    
    /// Join an existing room
    func joinRoom() {
        multipeerService.joinRoom()
    }
    
    /// Leave current room
    func leaveRoom() {
        stopSharing()
        multipeerService.leaveRoom()
    }
    
    /// Start sharing local camera
    func startSharing() {
        guard !isSharing else { return }
        isSharing = true
        
        // Start camera if needed
        setupCameraIfAuthorized()
        
        // Notify peers
        multipeerService.sendCameraStatus(isSharing: true)
        
        updatePlaceholder()
    }
    
    /// Stop sharing local camera
    func stopSharing() {
        guard isSharing else { return }
        isSharing = false
        
        // Notify peers
        multipeerService.sendCameraStatus(isSharing: false)
        
        // Stop camera
        cameraRenderer?.stop()
        cameraRenderer = nil
        
        updatePlaceholder()
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .voiceChat, options: [.mixWithOthers, .allowBluetooth])
            try audioSession.setActive(true)
            print("[SharedCameraProvider] Audio session configured for VoIP")
        } catch {
            print("[SharedCameraProvider] Failed to configure audio session: \(error)")
        }
    }
    
    private func setupCameraIfAuthorized() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.showError("需要相机权限")
                    }
                }
            }
        case .denied, .restricted:
            showError("请在设置中开启相机权限")
        @unknown default:
            showError("相机不可用")
        }
    }
    
    private func setupCamera() {
        guard let layer = outputLayer, cameraRenderer == nil else { return }
        
        print("[SharedCameraProvider] Setting up camera...")
        
        cameraRenderer = SharedCameraRenderer(delegate: self)
        cameraRenderer?.start()
        
        placeholderLabel.isHidden = true
    }
    
    private func setupDisplayLink() {
        displayLink?.invalidate()
        
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(preferredFrameRate),
                maximum: Float(preferredFrameRate),
                preferred: Float(preferredFrameRate)
            )
        } else {
            displayLink?.preferredFramesPerSecond = preferredFrameRate
        }
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard isRunning else { return }
        
        // Frame rate limiting
        let currentTime = link.timestamp
        guard currentTime - lastOutputTime >= outputFrameInterval else { return }
        lastOutputTime = currentTime
        
        // Get latest frames
        frameLock.lock()
        let localFrame = latestLocalFrame
        let remoteFrame = latestRemoteFrame
        frameLock.unlock()
        
        // Composite frames
        guard let compositor = compositor,
              let sampleBuffer = compositor.composite(local: localFrame, remote: remoteFrame) else {
            return
        }
        
        // Output to display layer
        guard let layer = outputLayer else { return }
        
        if layer.status == .failed {
            layer.flush()
        }
        
        layer.enqueue(sampleBuffer)
        
        // Send to peers if sharing
        if isSharing && multipeerService.state.isActive {
            multipeerService.sendVideoFrame(sampleBuffer)
        }
    }
    
    private func setupAppLifecycleHandling() {
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[SharedCameraProvider] App became active")
            }
        }
    }
    
    private func showError(_ message: String) {
        placeholderLabel.text = message
        placeholderLabel.isHidden = false
    }
    
    private func updatePlaceholder() {
        var statusParts: [String] = []
        
        switch multipeerService.state {
        case .idle:
            statusParts.append("未连接房间")
        case .creating:
            statusParts.append("创建房间中...")
        case .joining:
            statusParts.append("加入房间中...")
        case .connected(let roomName):
            let participantCount = multipeerService.participants.count
            statusParts.append("\(roomName) (\(participantCount)人)")
        case .disconnected(let reason):
            statusParts.append("已断开: \(reason)")
        }
        
        if isSharing {
            statusParts.append("正在共享")
        }
        
        let statusText = statusParts.joined(separator: "\n")
        placeholderLabel.text = statusText
        
        // Hide placeholder if we have video
        let hasVideo = latestLocalFrame != nil || latestRemoteFrame != nil
        placeholderLabel.isHidden = hasVideo
    }
}

// MARK: - SharedCameraRendererDelegate

extension SharedCameraProvider: SharedCameraRendererDelegate {
    
    func sharedCameraRenderer(_ renderer: SharedCameraRenderer, didOutputPixelBuffer pixelBuffer: CVPixelBuffer) {
        frameLock.lock()
        latestLocalFrame = pixelBuffer
        frameLock.unlock()
    }
}

// MARK: - MultipeerServiceDelegate

extension SharedCameraProvider: MultipeerServiceDelegate {
    
    func multipeerService(_ service: MultipeerService, didChangeState state: RoomState) {
        updatePlaceholder()
    }
    
    func multipeerService(_ service: MultipeerService, didUpdateParticipants participants: [RoomParticipant]) {
        updatePlaceholder()
    }
    
    func multipeerService(_ service: MultipeerService, didReceiveVideoFrame frame: CMSampleBuffer, from peerId: String) {
        // Only process frames from selected peer or first peer if none selected
        guard peerId == service.selectedRemotePeerId || service.selectedRemotePeerId == nil else {
            return
        }
        
        // Extract pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else { return }
        
        frameLock.lock()
        latestRemoteFrame = pixelBuffer
        frameLock.unlock()
    }
    
    func multipeerService(_ service: MultipeerService, peerDidStartSharing peerId: String) {
        print("[SharedCameraProvider] Peer started sharing: \(peerId)")
        
        // Auto-select this peer if none selected
        if service.selectedRemotePeerId == nil {
            service.selectedRemotePeerId = peerId
        }
        
        updatePlaceholder()
    }
    
    func multipeerService(_ service: MultipeerService, peerDidStopSharing peerId: String) {
        print("[SharedCameraProvider] Peer stopped sharing: \(peerId)")
        
        // Clear remote frame if this was the selected peer
        if service.selectedRemotePeerId == peerId {
            frameLock.lock()
            latestRemoteFrame = nil
            frameLock.unlock()
        }
        
        updatePlaceholder()
    }
}

// MARK: - Shared Camera Renderer

/// Delegate for receiving camera frames
protocol SharedCameraRendererDelegate: AnyObject {
    func sharedCameraRenderer(_ renderer: SharedCameraRenderer, didOutputPixelBuffer pixelBuffer: CVPixelBuffer)
}

/// Camera renderer optimized for shared streaming
final class SharedCameraRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Fixed output size (same as network transmission)
    private static let outputWidth: Int = 400
    private static let outputHeight: Int = 200
    
    weak var delegate: SharedCameraRendererDelegate?
    
    private var captureSession: AVCaptureSession?
    private let outputQueue = DispatchQueue(label: "com.porthole.shared-camera.output", qos: .userInitiated)
    
    // Pixel buffer pool for output
    private var outputPixelBufferPool: CVPixelBufferPool?
    
    // Core Image context for processing
    private let ciContext: CIContext
    
    // Cached transforms
    private var cachedCropRect: CGRect?
    private var cachedScaleTransform: CGAffineTransform?
    private var lastSourceSize: CGSize = .zero
    
    init(delegate: SharedCameraRendererDelegate?) {
        self.delegate = delegate
        
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
        setupOutputPixelBufferPool()
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
    }
    
    func start() {
        let session = AVCaptureSession()
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
            print("[SharedCameraRenderer] Failed to setup camera")
            return
        }
        
        // Configure camera for 15fps
        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            camera.unlockForConfiguration()
        } catch {
            print("[SharedCameraRenderer] Failed to configure camera: \(error)")
        }
        
        session.addInput(input)
        
        // Add video data output
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
            print("[SharedCameraRenderer] Started")
        }
    }
    
    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        print("[SharedCameraRenderer] Stopped")
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process frame
        guard let outputBuffer = processFrame(sourceBuffer) else { return }
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.sharedCameraRenderer(self, didOutputPixelBuffer: outputBuffer)
        }
    }
    
    private func processFrame(_ sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool = outputPixelBufferPool else { return nil }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
        
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
}
