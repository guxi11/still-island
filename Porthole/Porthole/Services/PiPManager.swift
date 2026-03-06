//
//  PiPManager.swift
//  Porthole
//
//  Manages Picture-in-Picture window lifecycle using VoIP mode.
//  Uses AVPictureInPictureVideoCallViewController for clean PiP without playback controls.
//

import UIKit
import AVKit
import Combine
import CoreMedia

// MARK: - PiP Content View Controller

/// UIViewController that hosts the PiP content using AVSampleBufferDisplayLayer
final class PiPContentViewController: AVPictureInPictureVideoCallViewController {
    
    private var sampleBufferView: SampleBufferDisplayView?
    
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer? {
        sampleBufferView?.sampleBufferDisplayLayer
    }
    
    /// 设置显示视图（在 PiP 启动前调用）
    func setupDisplayView(_ view: SampleBufferDisplayView) {
        // 移除旧的视图
        sampleBufferView?.removeFromSuperview()
        
        sampleBufferView = view
        
        // 关键：在添加约束前先设置初始 frame 为 preferredContentSize
        // 这样可以避免 layer 从小尺寸开始导致的缩放动画
        view.frame = CGRect(origin: .zero, size: preferredContentSize)
        view.layoutIfNeeded()
        
        view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: self.view.topAnchor),
            view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        
        // 立即布局，确保约束生效后尺寸正确
        self.view.layoutIfNeeded()
    }
    
    override var preferredContentSize: CGSize {
        get { CGSize(width: 400, height: 200) }  // 2:1 aspect ratio
        set { }
    }
}

// MARK: - PiPManager

/// Singleton manager for Picture-in-Picture functionality.
/// Uses VoIP mode (AVPictureInPictureVideoCallViewController) for clean PiP without buttons.
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

    /// The display layer for preview
    var displayLayer: AVSampleBufferDisplayLayer? {
        pipContentViewController?.sampleBufferDisplayLayer
    }

    // MARK: - Private Properties

    private var pipController: AVPictureInPictureController?
    private var pipContentViewController: PiPContentViewController?
    private var videoStreamConverter: ViewToVideoStreamConverter?
    private var currentProvider: PiPContentProvider?

    /// Whether current provider uses direct video output
    private var isDirectVideoProvider: Bool = false

    /// Source view for VoIP PiP (must remain in view hierarchy)
    private var pipSourceView: UIView?
    
    // Reference to the view that hosts the display layer (for fallback mode)
    private weak var hostView: SampleBufferDisplayView?

    // Audio session configuration
    private var isAudioSessionConfigured = false

    // KVO observation
    private var pipPossibleObservation: NSKeyValueObservation?

    // Timer for updating content
    private var updateTimer: Timer?
    
    // 准备超时任务
    private var prepareTimeoutTask: Task<Void, Never>?
    
    // 热状态监控
    private var thermalStateObserver: NSObjectProtocol?
    private var lowPowerModeObserver: NSObjectProtocol?

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
        
        // 监控设备热状态变化
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleThermalStateChange()
            }
        }
        
        // 监控低电量模式变化
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePowerStateChange()
            }
        }
    }
    
    /// 清理观察者
    private func removeLifecycleObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }
        if let observer = lowPowerModeObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerModeObserver = nil
        }
    }
    
    deinit {
        // 注意：由于是单例，deinit通常不会被调用，但为了代码完整性保留
        Task { @MainActor [weak self] in
            self?.removeLifecycleObservers()
        }
    }
    
    /// 处理热状态变化 - 设备过热时降低帧率
    private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        print("[PiPManager] Thermal state changed: \(thermalState.rawValue)")
        
        guard isPiPActive, let provider = currentProvider else { return }
        
        let baseFrameRate = provider.preferredFrameRate
        let adjustedFrameRate: Int
        
        switch thermalState {
        case .nominal:
            adjustedFrameRate = baseFrameRate
        case .fair:
            // 轻微发热，降低20%帧率
            adjustedFrameRate = max(1, Int(Double(baseFrameRate) * 0.8))
        case .serious:
            // 严重发热，降低50%帧率
            adjustedFrameRate = max(1, baseFrameRate / 2)
        case .critical:
            // 临界状态，最低帧率
            adjustedFrameRate = max(1, baseFrameRate / 4)
        @unknown default:
            adjustedFrameRate = baseFrameRate
        }
        
        if adjustedFrameRate != currentFrameRate {
            print("[PiPManager] Adjusting frame rate from \(currentFrameRate) to \(adjustedFrameRate) due to thermal state")
            setFrameRate(adjustedFrameRate)
        }
    }
    
    /// 处理电源状态变化 - 低电量模式时降低帧率
    private func handlePowerStateChange() {
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        print("[PiPManager] Low power mode: \(isLowPowerMode)")
        
        guard isPiPActive, let provider = currentProvider else { return }
        
        let baseFrameRate = provider.preferredFrameRate
        let adjustedFrameRate: Int
        
        if isLowPowerMode {
            // 低电量模式，降低50%帧率
            adjustedFrameRate = max(1, baseFrameRate / 2)
        } else {
            // 检查热状态，可能需要保持较低帧率
            let thermalState = ProcessInfo.processInfo.thermalState
            if thermalState == .nominal {
                adjustedFrameRate = baseFrameRate
            } else {
                // 保持当前帧率，让热状态处理函数决定
                return
            }
        }
        
        if adjustedFrameRate != currentFrameRate {
            print("[PiPManager] Adjusting frame rate from \(currentFrameRate) to \(adjustedFrameRate) due to power state")
            setFrameRate(adjustedFrameRate)
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("[PiPManager] App entering background")
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("[PiPManager] App entering foreground")
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

        // Check if provider uses direct video output
        if let directProvider = provider as? DirectVideoProvider, directProvider.providesDirectVideoOutput {
            print("[PiPManager] Provider supports direct video output")
            isDirectVideoProvider = true
        } else {
            print("[PiPManager] Provider uses UIView capture")
            isDirectVideoProvider = false
        }
        
        // Create VoIP PiP content view controller
        setupVoIPPiP(provider: provider)
    }
    
    // MARK: - VoIP PiP Setup
    
    private func setupVoIPPiP(provider: PiPContentProvider) {
        // Create the content view controller
        let contentVC = PiPContentViewController()
        pipContentViewController = contentVC
        
        // 创建用于 PiP 内显示的 SampleBufferDisplayView
        let pipDisplayView = SampleBufferDisplayView()
        contentVC.setupDisplayView(pipDisplayView)
        
        // Setup provider with the display layer
        if let directProvider = provider as? DirectVideoProvider {
            directProvider.setOutputLayer(pipDisplayView.sampleBufferDisplayLayer)
        } else {
            // For view-based providers, setup converter
            let converter = ViewToVideoStreamConverter()
            videoStreamConverter = converter
            
            converter.onScreenOff = { [weak self] in
                guard self != nil else { return }
                Task { @MainActor in
                    DisplayTimeTracker.shared.handleScreenOff()
                }
            }
            converter.onScreenOn = { [weak self] in
                guard self != nil else { return }
                Task { @MainActor in
                    DisplayTimeTracker.shared.handleScreenOn()
                }
            }
            
            let contentView = provider.contentView
            if contentView.bounds.size.width == 0 || contentView.bounds.size.height == 0 {
                contentView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
            }
            contentView.layoutIfNeeded()
            
            converter.setContentView(contentView)
            converter.setDisplayLayer(pipDisplayView.sampleBufferDisplayLayer)
            converter.startCapture(frameRate: provider.preferredFrameRate)
        }
        
        // Start the provider
        provider.start()
        
        print("[PiPManager] VoIP PiP content view controller prepared, waiting for view binding...")
    }

    /// Binds the converter to the view's display layer and starts capture.
    func bindToViewLayer(_ view: SampleBufferDisplayView) {
        print("[PiPManager] Binding to view's display layer")
        hostView = view
        
        // Create source view for VoIP PiP
        let sourceView = view
        pipSourceView = sourceView
        
        // Setup VoIP PiP controller
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.setupVoIPPiPController()
        }
    }
    
    private func setupVoIPPiPController() {
        guard let sourceView = pipSourceView,
              let contentVC = pipContentViewController else {
            print("[PiPManager] setupVoIPPiPController: missing source view or content VC")
            return
        }
        
        guard sourceView.window != nil else {
            print("[PiPManager] setupVoIPPiPController: source view not in window, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setupVoIPPiPController()
            }
            return
        }
        
        if pipController != nil {
            print("[PiPManager] PiP controller already exists")
            return
        }
        
        print("[PiPManager] Creating VoIP PiP controller")
        
        // Create ContentSource with VoIP support (iOS 15+)
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        
        // Create PiP controller with VoIP content source
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        
        // VoIP mode specific settings
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        
        pipController = controller
        
        print("[PiPManager] VoIP PiP controller created, isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")
        
        // Observe isPictureInPicturePossible changes
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] pipController, change in
            Task { @MainActor in
                let possible = change.newValue ?? false
                print("[PiPManager] KVO: isPictureInPicturePossible changed to: \(possible)")
                self?.isPiPPossible = possible
                
                if possible && self?.isPreparingPiP == true && self?.isPiPActive == false {
                    print("[PiPManager] KVO: Auto-starting VoIP PiP now!")
                    pipController.startPictureInPicture()
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
            print("[PiPManager] Starting VoIP PiP...")
            controller.startPictureInPicture()
        } else {
            print("[PiPManager] VoIP PiP not possible yet, attempting anyway...")
            controller.startPictureInPicture()
        }
    }

    /// Stops the current PiP session.
    func stopPiP() {
        print("[PiPManager] stopPiP called")
        
        // 取消准备超时任务
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil

        // Cancel KVO observations
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil

        updateTimer?.invalidate()
        updateTimer = nil

        // Stop PiP controller
        pipController?.stopPictureInPicture()

        // Stop video converter
        videoStreamConverter?.stopCapture()
        videoStreamConverter = nil

        // Stop and release provider
        if let provider = currentProvider {
            provider.contentView.removeFromSuperview()
            provider.stop()
        }
        currentProvider = nil

        // Clean up VoIP PiP
        pipContentViewController = nil
        pipSourceView = nil
        
        // Release PiP controller
        pipController = nil
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
        
        if let controller = pipController, controller.isPictureInPicturePossible {
            print("[PiPManager] Starting VoIP PiP immediately")
            controller.startPictureInPicture()
        } else {
            print("[PiPManager] Waiting for VoIP PiP to become possible...")
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
            // 使用 playAndRecord 类别配合 voiceChat 模式以支持 VoIP PiP
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
            isAudioSessionConfigured = true
            print("[PiPManager] Audio session configured for VoIP successfully")
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
            print("[PiPManager] VoIP PiP will start")
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

            print("[PiPManager] VoIP PiP did start successfully!")
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            print("[PiPManager] VoIP PiP will stop")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false

            // Stop tracking display time
            DisplayTimeTracker.shared.stopTracking()

            print("[PiPManager] VoIP PiP did stop")
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            print("[PiPManager] ERROR: VoIP PiP failed to start: \(error)")
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
