//
//  CameraProvider.swift
//  Still Island
//
//  Provides rear camera (实景) preview for PiP display.
//  Uses AVCaptureVideoPreviewLayer for better system integration.
//

import UIKit
import AVFoundation
import CoreMedia

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
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let placeholderLabel: UILabel
    private var isRunning = false
    
    // Notification observers
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndedObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    override init() {
        // Create container view
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black
        container.clipsToBounds = true
        
        // Create placeholder label
        let label = UILabel(frame: container.bounds)
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.text = "实景加载中..."
        label.backgroundColor = .clear
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(label)
        
        self.contentView = container
        self.placeholderLabel = label
        
        super.init()
        
        print("[CameraProvider] Initialized")
    }
    
    deinit {
        // Clean up observers
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionEndedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[CameraProvider] start()")
        
        guard !isRunning else { return }
        isRunning = true
        
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
        
        // Remove notification observers
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = interruptionEndedObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionEndedObserver = nil
        }
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }
        
        captureSession?.stopRunning()
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        captureSession = nil
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        print("[CameraProvider] Setting up camera...")
        
        // Configure audio session
        configureAudioSession()
        
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        // Enable multitasking camera access (iOS 16+)
        if #available(iOS 16.0, *) {
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
                print("[CameraProvider] Multitasking camera access enabled")
            } else {
                print("[CameraProvider] Multitasking camera access not supported")
            }
        }
        
        // Get the back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            showError("未找到相机")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            showError("相机初始化失败")
            print("[CameraProvider] Error: \(error)")
            return
        }
        
        self.captureSession = session
        
        // Create and add preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = contentView.bounds
        
        // Set video orientation
        if let connection = preview.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        
        contentView.layer.insertSublayer(preview, at: 0)
        self.previewLayer = preview
        
        // Hide placeholder
        placeholderLabel.isHidden = true
        
        // Setup interruption handling
        setupInterruptionHandling(for: session)
        
        // Setup app lifecycle handling
        setupAppLifecycleHandling(for: session)
        
        // Start capture session on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            print("[CameraProvider] Camera session started")
        }
    }
    
    /// Setup notification handlers for capture session interruption
    private func setupInterruptionHandling(for session: AVCaptureSession) {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { notification in
            if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
               let interruptionReason = AVCaptureSession.InterruptionReason(rawValue: reason) {
                print("[CameraProvider] Session interrupted: \(interruptionReason.rawValue)")
            } else {
                print("[CameraProvider] Session interrupted (unknown reason)")
            }
        }
        
        let capturedSession = session
        interruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            print("[CameraProvider] Session interruption ended")
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                if !capturedSession.isRunning {
                    DispatchQueue.global(qos: .userInitiated).async {
                        capturedSession.startRunning()
                        print("[CameraProvider] Session resumed")
                    }
                }
            }
        }
    }
    
    /// Setup app lifecycle handling to resume camera when returning to foreground
    private func setupAppLifecycleHandling(for session: AVCaptureSession) {
        let capturedSession = session
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[CameraProvider] App became active, checking session...")
                if !capturedSession.isRunning {
                    DispatchQueue.global(qos: .userInitiated).async {
                        capturedSession.startRunning()
                        print("[CameraProvider] Session restarted on app active")
                    }
                }
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
    
    // Called when contentView's bounds change
    func updatePreviewLayerFrame() {
        previewLayer?.frame = contentView.bounds
    }
}
