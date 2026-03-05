//
//  PiPManager.swift
//  Porthole
//
//  Manages Picture-in-Picture window lifecycle using AVSampleBufferDisplayLayer.
//  Uses AVPictureInPictureController.ContentSource for direct sample buffer display.
//

import UIKit
import AVKit
import Combine
import CoreMedia

/// Singleton manager for Picture-in-Picture functionality.
/// Uses AVSampleBufferDisplayLayer with ContentSource for PiP display.
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
        if directVideoDisplayLayer != nil {
            return directVideoDisplayLayer
        }
        return videoStreamConverter?.displayLayer
    }

    // MARK: - Private Properties

    private var pipController: AVPictureInPictureController?
    private var videoStreamConverter: ViewToVideoStreamConverter?
    private var currentProvider: PiPContentProvider?

    /// Display layer for DirectVideoProvider (camera, etc.)
    private var directVideoDisplayLayer: AVSampleBufferDisplayLayer?

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
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        directVideoDisplayLayer = layer

        provider.setOutputLayer(layer)

        let contentView = provider.contentView
        if contentView.bounds.size.width == 0 || contentView.bounds.size.height == 0 {
            contentView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        }
        contentView.layoutIfNeeded()

        print("[PiPManager] Direct video provider prepared, waiting for view binding...")
    }

    // MARK: - View-Based Provider Setup

    private func prepareViewBasedProvider(_ provider: PiPContentProvider) {
        let converter = ViewToVideoStreamConverter()
        videoStreamConverter = converter

        // 使用 [weak self] 避免循环引用
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

        print("[PiPManager] Content view size: \(contentView.bounds.size)")

        converter.setContentView(contentView)

        print("[PiPManager] View-based provider prepared, waiting for view binding...")
    }

    /// Binds the converter to the view's display layer and starts capture.
    func bindToViewLayer(_ view: SampleBufferDisplayView) {
        print("[PiPManager] Binding to view's display layer")
        hostView = view

        if isDirectVideoProvider {
            let viewLayer = view.sampleBufferDisplayLayer

            if let directLayer = directVideoDisplayLayer {
                viewLayer.videoGravity = directLayer.videoGravity
                viewLayer.backgroundColor = directLayer.backgroundColor
            }

            if let directProvider = currentProvider as? DirectVideoProvider {
                directProvider.setOutputLayer(viewLayer)
            }

            currentProvider?.start()

            print("[PiPManager] Direct video provider started")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupPiPController()
            }
        } else {
            guard let converter = videoStreamConverter else {
                print("[PiPManager] bindToViewLayer: no converter")
                return
            }

            let viewLayer = view.sampleBufferDisplayLayer
            converter.setDisplayLayer(viewLayer)

            print("[PiPManager] View layer: \(viewLayer)")

            converter.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)

            currentProvider?.start()

            print("[PiPManager] Video capture started")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupPiPController()
            }
        }
    }

    /// Sets up the PiP controller using AVSampleBufferDisplayLayer with ContentSource
    private func setupPiPController() {
        guard let view = hostView else {
            print("[PiPManager] setupPiPController: no host view")
            return
        }

        guard view.window != nil else {
            print("[PiPManager] setupPiPController: view not in window, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setupPiPController()
            }
            return
        }

        if pipController != nil {
            print("[PiPManager] PiP controller already exists")
            return
        }

        print("[PiPManager] Creating PiP controller using AVSampleBufferDisplayLayer ContentSource")

        // Get the sample buffer display layer from the host view
        let sampleBufferLayer = view.sampleBufferDisplayLayer

        // Create ContentSource with AVSampleBufferDisplayLayer (iOS 15+)
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferLayer,
            playbackDelegate: self
        )

        // Create PiP controller with content source
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self

        // 不自动从inline启动PiP
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        
        // 隐藏快进/快退按钮
        controller.requiresLinearPlayback = true

        pipController = controller

        print("[PiPManager] PiP controller created, isPictureInPicturePossible: \(controller.isPictureInPicturePossible)")

        // Observe isPictureInPicturePossible changes using KVO
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] pipController, change in
            Task { @MainActor in
                let possible = change.newValue ?? false
                print("[PiPManager] KVO: isPictureInPicturePossible changed to: \(possible)")
                self?.isPiPPossible = possible

                if possible && self?.isPreparingPiP == true && self?.isPiPActive == false {
                    print("[PiPManager] KVO: Auto-starting PiP now!")
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

        // Clean up direct video layer
        directVideoDisplayLayer = nil

        // Stop and release provider
        if let provider = currentProvider {
            provider.contentView.removeFromSuperview()
            provider.stop()
        }
        currentProvider = nil

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
            print("[PiPManager] Starting PiP immediately")
            controller.startPictureInPicture()
        } else {
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
            // 使用playback类别，支持后台音频播放
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

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // 忽略播放/暂停请求，内容持续运行
    }
    
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // 返回一个有限的时间范围，避免显示"直播"标签
        return CMTimeRange(start: .zero, duration: CMTime(value: Int64.max / 2, timescale: 1))
    }
    
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        // 始终返回 false（播放中），不显示暂停状态
        return false
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // 渲染尺寸变化，可忽略
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        // 不支持跳过
    }
}
