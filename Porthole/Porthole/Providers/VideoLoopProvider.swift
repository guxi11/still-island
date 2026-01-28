//
//  VideoLoopProvider.swift
//  Porthole
//
//  Provides looping video playback for PiP display using SpriteKit.
//  Uses the same technique as CatCompanionProvider for consistent PiP behavior.
//

import UIKit
import AVFoundation
import SpriteKit

/// A content provider that plays video in a loop for PiP window using SpriteKit.
/// This approach is identical to CatCompanionProvider for reliable PiP support.
@MainActor
final class VideoLoopProvider: NSObject, PiPContentProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "video"
    static let displayName: String = "视频"
    static let iconName: String = "play.rectangle.fill"

    // MARK: - PiPContentProvider Properties

    let contentView: UIView  // This holds our SKView
    let preferredFrameRate: Int = 30

    // MARK: - Private Properties

    private let skView: SKView
    private let videoScene: VideoScene
    private let placeholderLabel: UILabel
    private var isRunning = false
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Public Properties

    /// The currently selected video URL
    private(set) var videoURL: URL?

    /// Callback when video selection is needed
    var onNeedVideoSelection: (() -> Void)?

    // MARK: - Initialization

    override init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)

        // Setup SKView
        skView = SKView(frame: CGRect(origin: .zero, size: containerSize))
        skView.backgroundColor = .black
        skView.ignoresSiblingOrder = true
        // skView.showsFPS = true // Debug

        // Setup Scene
        videoScene = VideoScene(size: containerSize)
        videoScene.scaleMode = .resizeFill

        // Create placeholder label
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.text = "点击选择视频"
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false

        self.contentView = skView
        self.placeholderLabel = label

        super.init()

        // Add placeholder label to SKView
        skView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: skView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: skView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: skView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: skView.trailingAnchor, constant: -8)
        ])

        // Setup loading state callback
        videoScene.onLoadingStateChanged = { [weak self] isLoading, message in
            Task { @MainActor in
                self?.handleLoadingState(isLoading: isLoading, message: message)
            }
        }

        // Setup notifications for background handling
        setupNotifications()

        print("[VideoLoopProvider] Initialized with SKView (SpriteKit approach)")
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Private Methods

    private func setupNotifications() {
        // When app enters background, ensure SKView continues running for PiP
        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.skView.isPaused = false
            print("[VideoLoopProvider] App will resign active - keeping SKView running")
        }
        notificationObservers.append(resignObserver)

        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.skView.isPaused = false
            print("[VideoLoopProvider] App entered background - ensuring SKView is not paused")
        }
        notificationObservers.append(backgroundObserver)
    }

    private func handleLoadingState(isLoading: Bool, message: String?) {
        if isLoading {
            placeholderLabel.text = message ?? "加载中..."
            placeholderLabel.isHidden = false
        } else if let error = message {
            placeholderLabel.text = error
            placeholderLabel.isHidden = false
        } else {
            placeholderLabel.isHidden = true
            // Start animation when loading is complete
            if isRunning {
                videoScene.startAnimation()
            }
        }
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[VideoLoopProvider] start()")

        guard !isRunning else { return }
        isRunning = true

        // Configure audio session
        configureAudioSession()

        // Ensure SKView is not paused
        skView.isPaused = false

        // Present the scene
        if skView.scene == nil {
            skView.presentScene(videoScene)
        }

        // Load video if URL is set
        if let url = videoURL {
            videoScene.loadVideo(from: url)
        } else {
            placeholderLabel.text = "未选择视频"
            placeholderLabel.isHidden = false
        }
    }

    func stop() {
        print("[VideoLoopProvider] stop()")
        isRunning = false

        // Stop animation but don't pause SKView (for PiP)
        videoScene.stopAnimation()
    }

    // MARK: - Public Methods

    /// Set the video URL (persistence is handled by CardManager)
    func setVideoURL(_ url: URL) {
        print("[VideoLoopProvider] Setting video URL: \(url)")
        self.videoURL = url

        if isRunning {
            // Clear old frames and load new video
            videoScene.clearFrames()
            videoScene.loadVideo(from: url)
        }
    }

    /// Check if a video is currently selected
    var hasVideo: Bool {
        videoURL != nil
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
            print("[VideoLoopProvider] Audio session configured")
        } catch {
            print("[VideoLoopProvider] Failed to configure audio session: \(error)")
        }
    }
}
