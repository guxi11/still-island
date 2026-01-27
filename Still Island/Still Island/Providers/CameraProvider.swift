//
//  CameraProvider.swift
//  Still Island
//
//  Provides rear camera (实景) preview for PiP display.
//  Camera continues running when app enters background via PiP.
//

import UIKit
import AVFoundation

/// A content provider that displays rear camera preview in PiP window.
/// The camera session continues running when the app enters background.
@MainActor
final class CameraProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "camera"
    static let displayName: String = "实景"
    static let iconName: String = "video.fill"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 30
    
    // MARK: - Private Properties
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let placeholderLabel: UILabel
    private var isRunning = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        container.clipsToBounds = true
        
        // Create placeholder label (shown when camera is not available)
        let label = UILabel(frame: container.bounds)
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.text = "实景加载中..."
        label.backgroundColor = .clear
        container.addSubview(label)
        
        self.contentView = container
        self.placeholderLabel = label
        
        // Force layout
        container.setNeedsLayout()
        container.layoutIfNeeded()
        
        print("[CameraProvider] Initialized with view size: \(container.bounds.size)")
    }
    
    deinit {
        // Remove observers
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[CameraProvider] start()")
        
        guard !isRunning else { return }
        isRunning = true
        
        // Setup app lifecycle observers to keep camera running in background
        setupLifecycleObservers()
        
        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
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
        
        // Remove lifecycle observers
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
    
    // MARK: - Private Methods
    
    private func setupLifecycleObservers() {
        // When app enters background, keep camera running if PiP is active
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[CameraProvider] App entered background - keeping camera active for PiP")
            // Camera session continues running - no action needed
            // The PiP window will continue to display the camera feed
        }
        
        // When app returns to foreground
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[CameraProvider] App entering foreground")
            // Ensure camera is still running
            if let session = self?.captureSession, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }
    }
    
    private func setupCamera() {
        print("[CameraProvider] Setting up camera...")
        
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        // Configure session for background use
        session.automaticallyConfiguresApplicationAudioSession = false
        
        // Get the back camera (rear camera for "实景")
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
        
        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = contentView.bounds
        preview.videoGravity = .resizeAspectFill
        
        // No mirroring for back camera
        if let connection = preview.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        
        contentView.layer.insertSublayer(preview, at: 0)
        
        self.captureSession = session
        self.previewLayer = preview
        
        // Hide placeholder
        placeholderLabel.isHidden = true
        
        // Start capture session on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            print("[CameraProvider] Camera session started")
        }
    }
    
    private func showError(_ message: String) {
        placeholderLabel.text = message
        placeholderLabel.isHidden = false
    }
}
