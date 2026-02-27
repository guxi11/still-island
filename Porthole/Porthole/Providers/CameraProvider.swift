//
//  CameraProvider.swift
//  Porthole
//
//  Provides rear camera (实景) preview for PiP display.
//  Uses AVCaptureVideoPreviewLayer for better system integration.
//

import UIKit
import AVFoundation
import CoreMedia
import Combine

/// A content provider that displays rear camera preview in PiP window.
/// Uses AVCaptureVideoPreviewLayer directly embedded in contentView for
/// better compatibility with PiP and potential background operation.
@MainActor
final class CameraProvider: NSObject, PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "camera"
    static let displayName: String = "实景"
    static let iconName: String = "video.fill"
    
    // MARK: - PiPContentProvider Properties

    let contentView: UIView
    let preferredFrameRate: Int = 30

    // MARK: - Private Properties

    private let displayLayer: AVSampleBufferDisplayLayer
    private var renderer: CameraHardwareRenderer?
    private let placeholderLabel: UILabel
    private var isRunning = false
    
    // Notification observers
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    
    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false
    private var lastCelebratedIntervalId: UUID? // 防止重复触发
    
    // MARK: - Initialization
    
    override init() {
        // Create container view
        let containerSize = CGSize(width: 200, height: 100)
        let container = VideoLayerView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black
        container.clipsToBounds = true

        // Create display layer
        displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.frame = container.bounds
        displayLayer.videoGravity = .resizeAspectFill
        container.layer.insertSublayer(displayLayer, at: 0)

        // Create placeholder label
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.text = "实景加载中..."
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

        print("[CameraProvider] Initialized with hardware-accelerated renderer")
    }
    
    deinit {
        // Clean up observers
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        renderer?.stop()
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[CameraProvider] start()")
        
        guard !isRunning else { return }
        isRunning = true
        
        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()
        
        // Check camera authorization
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
    
    func stop() {
        print("[CameraProvider] stop()")
        isRunning = false

        // Clean up celebration
        cancellables.removeAll()
        removeCelebration()

        // Remove notification observers
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }

        renderer?.stop()
        renderer = nil
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        print("[CameraProvider] Setting up camera...")

        // Configure audio session
        configureAudioSession()

        // Hide placeholder
        placeholderLabel.isHidden = true

        // Create hardware renderer
        renderer = CameraHardwareRenderer(displayLayer: displayLayer)

        // Setup app lifecycle handling
        setupAppLifecycleHandling()

        // Start renderer
        renderer?.start()
    }
    
    /// Setup app lifecycle handling to resume camera when returning to foreground
    private func setupAppLifecycleHandling() {
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[CameraProvider] App became active")
            }
        }
    }
    
    private func showError(_ message: String) {
        placeholderLabel.text = message
        placeholderLabel.isHidden = false
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
            print("[CameraProvider] Audio session configured")
        } catch {
            print("[CameraProvider] Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Celebration
    
    private func setupCelebrationObserver() {
        print("[CameraProvider] Setting up celebration observer")
        
        // 先清除旧订阅，防止重复
        cancellables.removeAll()
        
        // Subscribe to away interval completion
        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let self = self else { return }
                // 防止对同一个 interval 重复触发庆祝
                guard self.lastCelebratedIntervalId != interval.id else { return }
                self.lastCelebratedIntervalId = interval.id
                print("[CameraProvider] Received away interval: \(interval.duration) seconds")
                self.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)
        
        print("[CameraProvider] Celebration observer setup complete")
    }
    
    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true
        
        print("[CameraProvider] Showing celebration for \(Int(duration)) seconds away")
        
        // Hide display layer during celebration
        displayLayer.isHidden = true
        placeholderLabel.isHidden = true
        
        // Create and show celebration view
        let celebration = CelebrationView(frame: contentView.bounds)
        celebration.awayDuration = duration
        celebration.onComplete = { [weak self] in
            self?.removeCelebration()
        }
        
        contentView.addSubview(celebration)
        celebrationView = celebration
        
        // Force layout update
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        
        // Start the celebration animation
        celebration.startCelebration()
        
        print("[CameraProvider] Celebration view added, frame: \(celebration.frame)")
    }
    
    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false
        
        // Show display layer again
        displayLayer.isHidden = false
        
        // Restore frame rate (CameraProvider already uses 30fps)
        DisplayTimeTracker.shared.clearLastAwayInterval()
        
        print("[CameraProvider] Celebration ended")
    }
}

