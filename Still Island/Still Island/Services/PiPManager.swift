//
//  PiPManager.swift
//  Still Island
//
//  Manages Picture-in-Picture window lifecycle using AVPictureInPictureVideoCallViewController.
//

import UIKit
import AVKit
import Combine

/// Singleton manager for Picture-in-Picture functionality.
/// Uses AVPictureInPictureVideoCallViewController for custom content display.
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
    
    // MARK: - Public Properties
    
    /// The display layer for preview (uses sample buffer approach for preview)
    var displayLayer: AVSampleBufferDisplayLayer? {
        return videoStreamConverter?.displayLayer
    }
    
    // MARK: - Private Properties
    
    private var pipController: AVPictureInPictureController?
    private var pipVideoCallVC: AVPictureInPictureVideoCallViewController?
    private var videoStreamConverter: ViewToVideoStreamConverter?
    private var currentProvider: PiPContentProvider?
    
    // Reference to the view that hosts the display layer
    private weak var hostView: SampleBufferDisplayView?
    
    // Audio session configuration
    private var isAudioSessionConfigured = false
    
    // KVO observation
    private var pipPossibleObservation: NSKeyValueObservation?
    
    // Timer for updating content
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        print("[PiPManager] Initializing...")
        configureAudioSession()
        print("[PiPManager] PiP supported: \(AVPictureInPictureController.isPictureInPictureSupported())")
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
        
        // Store provider
        currentProvider = provider
        
        // Create converter for preview
        let converter = ViewToVideoStreamConverter()
        videoStreamConverter = converter
        
        // Ensure the content view has valid size
        let contentView = provider.contentView
        if contentView.bounds.size.width == 0 || contentView.bounds.size.height == 0 {
            contentView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        }
        contentView.layoutIfNeeded()
        
        print("[PiPManager] Content view size: \(contentView.bounds.size)")
        
        converter.setContentView(contentView)
        
        // Start content provider
        provider.start()
        
        print("[PiPManager] Preparation complete. Waiting for view binding...")
    }
    
    /// Binds the converter to the view's display layer and starts capture.
    func bindToViewLayer(_ view: SampleBufferDisplayView) {
        guard let converter = videoStreamConverter else {
            print("[PiPManager] bindToViewLayer: no converter")
            return
        }
        
        print("[PiPManager] Binding to view's display layer")
        hostView = view
        
        // Switch to using the view's layer
        let viewLayer = view.sampleBufferDisplayLayer
        converter.setDisplayLayer(viewLayer)
        
        print("[PiPManager] View layer: \(viewLayer)")
        
        // Start video capture for preview
        converter.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)
        
        print("[PiPManager] Video capture started. Setting up PiP controller...")
        
        // Wait for view to be in window hierarchy, then setup controller
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupPiPController()
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
        
        // Add the time display view to the video call VC
        if let provider = currentProvider {
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
        
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        
        updateTimer?.invalidate()
        updateTimer = nil
        
        pipController?.stopPictureInPicture()
        
        videoStreamConverter?.stopCapture()
        videoStreamConverter = nil
        
        currentProvider?.stop()
        currentProvider = nil
        
        pipController = nil
        pipVideoCallVC = nil
        hostView = nil
        
        isPiPActive = false
        isPiPPossible = false
        isPlaying = true
        isPreparingPiP = false
        errorMessage = nil
    }
    
    /// Toggles pause/play state for the PiP content.
    func togglePlayPause() {
        isPlaying.toggle()
        
        if isPlaying {
            currentProvider?.start()
            videoStreamConverter?.startCapture(frameRate: currentProvider?.preferredFrameRate ?? 10)
        } else {
            videoStreamConverter?.stopCapture()
            currentProvider?.stop()
        }
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
            self.isPiPActive = true
            self.isPreparingPiP = false
            self.errorMessage = nil
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
