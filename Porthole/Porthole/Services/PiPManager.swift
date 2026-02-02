//
//  PiPManager.swift
//  Porthole
//
//  Manages Picture-in-Picture window lifecycle using AVPictureInPictureVideoCallViewController.
//  Supports UIView-based providers, DirectVideoProvider, and AVPlayerProvider.
//

import UIKit
import AVKit
import Combine

/// Singleton manager for Picture-in-Picture functionality.
/// Uses AVPictureInPictureVideoCallViewController for custom content display.
/// Uses standard AVPictureInPictureController for AVPlayer-based providers.
@MainActor
final class PiPManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = PiPManager()

    // MARK: - Published Properties

    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false
    @Published private(set) var isPlaying = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPreparingPiP = false
    @Published private(set) var currentProviderType: String?

    // MARK: - Public Properties

    /// The display layer for preview (uses sample buffer approach for preview)
    var displayLayer: AVSampleBufferDisplayLayer? {
        // For direct video providers, use the dedicated layer
        if directVideoDisplayLayer != nil {
            return directVideoDisplayLayer
        }
        return videoStreamConverter?.displayLayer
    }

    // MARK: - Private Properties

    private var pipController: AVPictureInPictureController?
    private var pipVideoCallVC: AVPictureInPictureVideoCallViewController?
    private var videoStreamConverter: ViewToVideoStreamConverter?
    private var currentProvider: PiPContentProvider?

    /// Display layer for DirectVideoProvider (camera, etc.)
    private var directVideoDisplayLayer: AVSampleBufferDisplayLayer?

    /// Display view inside the PiP window for direct video providers
    private var pipDisplayView: SampleBufferDisplayView?

    /// Whether current provider uses direct video output
    private var isDirectVideoProvider: Bool = false

    // Reference to the view that hosts the display layer
    private weak var hostView: SampleBufferDisplayView?

    // Audio session configuration
    private var isAudioSessionConfigured = false

    // KVO observation
    private var pipPossibleObservation: NSKeyValueObservation?

    // Timer for updating content
    private var updateTimer: Timer?
    
    // 准备超时任务
    private var prepareTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    private override init() {
        super.init()
        print("[PiPManager] Initializing...")
        configureAudioSession()
        setupLifecycleObservers()
        print("[PiPManager] PiP supported: \(AVPictureInPictureController.isPictureInPictureSupported())")
    }

    // MARK: - Lifecycle Observation
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("[PiPManager] App entering background")
        // Note: We do NOT stop the converter here if PiP is active.
        // The converter must continue running to update the PiP window content
        // even when the app is in the background.
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("[PiPManager] App entering foreground")
        // Ensure converter is running if needed
        if isPiPActive && !isDirectVideoProvider && isPlaying && !(videoStreamConverter?.isCapturing ?? false) {
            print("[PiPManager] Restarting preview converter for foreground check")
            videoStreamConverter?.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)
        }
    }

    // MARK: - Public Methods

    /// Prepares PiP with the specified content provider.
    func preparePiP(provider: PiPContentProvider) {
        print("[PiPManager] preparePiP called")

        // Stop any existing PiP
        stopPiP()

        // Configure audio session if needed
        if !isAudioSessionConfigured {
            configureAudioSession()
        }

        // Check PiP support
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiPManager] ERROR: PiP is not supported on this device")
            errorMessage = "此设备不支持画中画功能"
            return
        }

        isPreparingPiP = true
        
        // 设置准备超时（5秒）
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.isPreparingPiP == true && self?.isPiPActive == false {
                    print("[PiPManager] Prepare timeout, cancelling...")
                    self?.stopPiP()
                }
            }
        }

        // Store provider
        currentProvider = provider
        currentProviderType = type(of: provider).providerType

        // Check provider type and prepare accordingly
        if let directProvider = provider as? DirectVideoProvider, directProvider.providesDirectVideoOutput {
            print("[PiPManager] Provider supports direct video output")
            isDirectVideoProvider = true
            prepareDirectVideoProvider(directProvider)
        } else {
            print("[PiPManager] Provider uses UIView capture")
            isDirectVideoProvider = false
            prepareViewBasedProvider(provider)
        }
    }

    // MARK: - Direct Video Provider Setup

    private func prepareDirectVideoProvider(_ provider: DirectVideoProvider) {
        // Create a dedicated display layer for direct video
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        directVideoDisplayLayer = layer

        // Give the layer to the provider
        provider.setOutputLayer(layer)

        // Ensure the content view has valid size (for PiP VC)
        let contentView = provider.contentView
        if contentView.bounds.size.width == 0 || contentView.bounds.size.height == 0 {
            contentView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        }
        contentView.layoutIfNeeded()

        print("[PiPManager] Direct video provider prepared, waiting for view binding...")
    }

    // MARK: - View-Based Provider Setup

    private func prepareViewBasedProvider(_ provider: PiPContentProvider) {
        // Create converter for preview
        let converter = ViewToVideoStreamConverter()
        videoStreamConverter = converter

        // Setup screen state detection callbacks
        converter.onScreenOff = {
            Task { @MainActor in
                DisplayTimeTracker.shared.handleScreenOff()
            }
        }
        converter.onScreenOn = {
            Task { @MainActor in
                DisplayTimeTracker.shared.handleScreenOn()
            }
        }

        // Ensure the content view has valid size
        let contentView = provider.contentView
        if contentView.bounds.size.width == 0 || contentView.bounds.size.height == 0 {
            contentView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        }
        contentView.layoutIfNeeded()

        print("[PiPManager] Content view size: \(contentView.bounds.size)")

        converter.setContentView(contentView)

        print("[PiPManager] View-based provider prepared, waiting for view binding...")
    }

    /// Binds the converter to the view's display layer and starts capture.
    func bindToViewLayer(_ view: SampleBufferDisplayView) {
        print("[PiPManager] Binding to view's display layer")
        hostView = view

        if isDirectVideoProvider {
            // For direct video providers, we use the view's layer directly
            let viewLayer = view.sampleBufferDisplayLayer

            // Transfer configuration from our display layer to view's layer
            if let directLayer = directVideoDisplayLayer {
                viewLayer.videoGravity = directLayer.videoGravity
                viewLayer.backgroundColor = directLayer.backgroundColor
            }

            // Update provider with the actual view layer
            if let directProvider = currentProvider as? DirectVideoProvider {
                directProvider.setOutputLayer(viewLayer)
            }

            // Start the provider now
            currentProvider?.start()

            print("[PiPManager] Direct video provider started")

            // Wait for view to be in window hierarchy, then setup controller
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupPiPController()
            }
        } else {
            // For view-based providers, use the converter
            guard let converter = videoStreamConverter else {
                print("[PiPManager] bindToViewLayer: no converter")
                return
            }

            let viewLayer = view.sampleBufferDisplayLayer
            converter.setDisplayLayer(viewLayer)

            print("[PiPManager] View layer: \(viewLayer)")

            // Start video capture for preview
            converter.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)

            // Start the provider
            currentProvider?.start()

            print("[PiPManager] Video capture started")

            // Wait for view to be in window hierarchy, then setup controller
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupPiPController()
            }
        }
    }

    /// Sets up the PiP controller using AVPictureInPictureVideoCallViewController
    private func setupPiPController() {
        guard let view = hostView else {
            print("[PiPManager] setupPiPController: no host view")
            return
        }

        // Check if view is in window hierarchy
        guard let window = view.window else {
            print("[PiPManager] setupPiPController: view not in window, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setupPiPController()
            }
            return
        }

        // If we already have a controller, don't recreate
        if pipController != nil {
            print("[PiPManager] PiP controller already exists")
            return
        }

        print("[PiPManager] Creating PiP controller using VideoCallViewController approach")
        print("[PiPManager] View window: \(window)")

        // Create the video call view controller for PiP
        let videoCallVC = AVPictureInPictureVideoCallViewController()
        videoCallVC.preferredContentSize = CGSize(width: 200, height: 100)
        pipVideoCallVC = videoCallVC

        if isDirectVideoProvider {
            // For direct video providers, create a SampleBufferDisplayView inside the videoCallVC
            // This is where the camera frames will be displayed in the PiP window
            let displayView = SampleBufferDisplayView()
            displayView.translatesAutoresizingMaskIntoConstraints = false
            videoCallVC.view.addSubview(displayView)

            NSLayoutConstraint.activate([
                displayView.topAnchor.constraint(equalTo: videoCallVC.view.topAnchor),
                displayView.leadingAnchor.constraint(equalTo: videoCallVC.view.leadingAnchor),
                displayView.trailingAnchor.constraint(equalTo: videoCallVC.view.trailingAnchor),
                displayView.bottomAnchor.constraint(equalTo: videoCallVC.view.bottomAnchor)
            ])

            // Store reference to the PiP display view
            pipDisplayView = displayView

            // Connect the provider to this display layer
            if let directProvider = currentProvider as? DirectVideoProvider {
                directProvider.setOutputLayer(displayView.sampleBufferDisplayLayer)
                print("[PiPManager] Connected direct video provider to PiP display layer")
            }
        } else if let provider = currentProvider {
            let contentView = provider.contentView
            contentView.translatesAutoresizingMaskIntoConstraints = false
            videoCallVC.view.addSubview(contentView)

            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: videoCallVC.view.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: videoCallVC.view.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: videoCallVC.view.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: videoCallVC.view.bottomAnchor)
            ])
        }

        // Create content source using video call VC
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: videoCallVC
        )

        // Create controller
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self

        // Configure controller
        controller.canStartPictureInPictureAutomaticallyFromInline = false

        pipController = controller

        print("[PiPManager] PiP controller created, isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")

        // Observe isPictureInPicturePossible changes using KVO
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] controller, change in
            Task { @MainActor in
                let possible = change.newValue ?? false
                print("[PiPManager] KVO: isPictureInPicturePossible changed to: \(possible)")
                self?.isPiPPossible = possible

                if possible && self?.isPreparingPiP == true && self?.isPiPActive == false {
                    print("[PiPManager] KVO: Auto-starting PiP now!")
                    controller.startPictureInPicture()
                }
            }
        }

        // Try to start after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.tryStartPiP()
        }
    }

    private func tryStartPiP() {
        guard let controller = pipController else { return }

        print("[PiPManager] tryStartPiP - isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")

        if controller.isPictureInPicturePossible {
            print("[PiPManager] Starting PiP...")
            controller.startPictureInPicture()
        } else {
            print("[PiPManager] PiP not possible yet, attempting anyway...")
            controller.startPictureInPicture()
        }
    }

    /// Stops the current PiP session.
    func stopPiP() {
        print("[PiPManager] stopPiP called")
        
        // 取消准备超时任务
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil

        // Cancel KVO observation first
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil

        updateTimer?.invalidate()
        updateTimer = nil

        // Stop PiP controller
        pipController?.stopPictureInPicture()

        // Stop video converter (for view-based providers)
        videoStreamConverter?.stopCapture()
        videoStreamConverter = nil

        // Clean up direct video layer
        directVideoDisplayLayer = nil
        pipDisplayView = nil

        // Remove content view from video call VC before releasing
        if let provider = currentProvider {
            provider.contentView.removeFromSuperview()
        }

        // Stop and release provider
        currentProvider?.stop()
        currentProvider = nil

        // Release PiP controller and video call VC
        pipController = nil
        pipVideoCallVC = nil
        hostView = nil

        // Reset state
        isPiPActive = false
        isPiPPossible = false
        isPlaying = true
        isPreparingPiP = false
        errorMessage = nil
        currentProviderType = nil
        isDirectVideoProvider = false

        print("[PiPManager] stopPiP completed")
    }

    /// 取消 PiP 准备（上滑取消时调用）
    func cancelPrepare() {
        guard isPreparingPiP && !isPiPActive else { return }
        print("[PiPManager] cancelPrepare called")
        stopPiP()
    }
    
    /// 确认启动 PiP（上滑成功时调用，如果已经准备好就启动）
    func confirmStartPiP() {
        guard isPreparingPiP else { return }
        print("[PiPManager] confirmStartPiP called")
        
        // 如果 controller 已经存在且可用，立即启动
        if let controller = pipController, controller.isPictureInPicturePossible {
            print("[PiPManager] Starting PiP immediately")
            controller.startPictureInPicture()
        } else {
            // 等待 controller 准备好（KVO 会自动触发启动）
            print("[PiPManager] Waiting for PiP to become possible...")
        }
    }

    /// Toggles pause/play state for the PiP content.
    func togglePlayPause() {
        isPlaying.toggle()

        if isPlaying {
            currentProvider?.start()
            if !isDirectVideoProvider {
                videoStreamConverter?.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)
            }
        } else {
            if !isDirectVideoProvider {
                videoStreamConverter?.stopCapture()
            }
            currentProvider?.stop()
        }
    }

    /// Updates the frame rate for the video stream converter.
    /// Use higher frame rates (30) for animations, lower (10) for static content.
    /// - Parameter frameRate: Target frames per second (1-60).
    func setFrameRate(_ frameRate: Int) {
        videoStreamConverter?.setFrameRate(frameRate)
    }

    /// Returns the current frame rate of the video stream converter.
    var currentFrameRate: Int {
        videoStreamConverter?.currentFrameRate ?? 10
    }

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
            isAudioSessionConfigured = true
            print("[PiPManager] Audio session configured successfully")
        } catch {
            print("[PiPManager] ERROR: Failed to configure audio session: \(error)")
            errorMessage = "音频会话配置失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            print("[PiPManager] PiP will start")
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            // 取消准备超时任务
            self.prepareTimeoutTask?.cancel()
            self.prepareTimeoutTask = nil
            
            self.isPiPActive = true
            self.isPreparingPiP = false
            self.errorMessage = nil

            // Start tracking display time
            if let providerType = self.currentProviderType {
                DisplayTimeTracker.shared.startTracking(providerType: providerType)
            }

            print("[PiPManager] PiP did start successfully!")
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            print("[PiPManager] PiP will stop")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false

            // Stop tracking display time
            DisplayTimeTracker.shared.stopTracking()

            print("[PiPManager] PiP did stop")
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            print("[PiPManager] ERROR: PiP failed to start: \(error)")
            self.isPiPActive = false
            self.isPreparingPiP = false
            self.errorMessage = "启动失败: \(error.localizedDescription)"
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            completionHandler(true)
        }
    }
}
