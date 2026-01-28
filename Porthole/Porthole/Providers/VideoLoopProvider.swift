//
//  VideoLoopProvider.swift
//  Porthole
//
//  Provides looping video playback for PiP display.
//  Supports selecting videos from photo library.
//

import UIKit
import AVFoundation
import Combine

/// A content provider that plays video in a loop for PiP window.
@MainActor
final class VideoLoopProvider: NSObject, PiPContentProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "video"
    static let displayName: String = "视频"
    static let iconName: String = "play.rectangle.fill"

    // MARK: - PiPContentProvider Properties

    let contentView: UIView
    let preferredFrameRate: Int = 30

    // MARK: - Private Properties

    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var _playerLayer: AVPlayerLayer?
    private let placeholderLabel: UILabel
    private var isRunning = false

    // Video URL storage
    private static let videoURLKey = "VideoLoopProvider.savedVideoURL"

    // Notification observers
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var appWillResignActiveObserver: NSObjectProtocol?
    private var appDidEnterBackgroundObserver: NSObjectProtocol?
    private var playerItemDidPlayToEndObserver: NSObjectProtocol?

    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false

    // MARK: - Public Properties

    /// The currently selected video URL
    private(set) var videoURL: URL?

    /// Callback when video selection is needed
    var onNeedVideoSelection: (() -> Void)?

    // MARK: - Initialization

    override init() {
        // Create container view
        let containerSize = CGSize(width: 200, height: 100)
        let container = VideoContainerView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black
        container.clipsToBounds = true

        // Create placeholder label
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.text = "点击选择视频"
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

        // Video URL is now set externally via setVideoURL() from CardManager
        print("[VideoLoopProvider] Initialized")
    }

    deinit {
        // Clean up observers directly without calling MainActor method
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appWillResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playerItemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[VideoLoopProvider] start()")

        guard !isRunning else { return }
        isRunning = true

        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()

        // Configure audio session for background playback
        configureAudioSession()

        // Setup app lifecycle handling
        setupAppLifecycleHandling()

        if let url = videoURL {
            setupPlayer(with: url)
        } else {
            placeholderLabel.text = "未选择视频"
            placeholderLabel.isHidden = false
        }
    }

    func stop() {
        print("[VideoLoopProvider] stop()")
        isRunning = false

        // Clean up celebration
        cancellables.removeAll()
        removeCelebration()

        // Remove notification observers
        removeAllObservers()

        // Stop and clean up player
        player?.pause()
        playerLooper?.disableLooping()
        _playerLayer?.removeFromSuperlayer()
        _playerLayer = nil
        playerLooper = nil
        player = nil
    }

    // MARK: - Public Methods

    /// Set the video URL (persistence is handled by CardManager)
    func setVideoURL(_ url: URL) {
        print("[VideoLoopProvider] Setting video URL: \(url)")
        self.videoURL = url

        if isRunning {
            // Restart with new video
            cleanupPlayer()
            setupPlayer(with: url)
        }
    }

    /// Check if a video is currently selected
    var hasVideo: Bool {
        videoURL != nil
    }

    // MARK: - Private Methods

    private func setupPlayer(with url: URL) {
        print("[VideoLoopProvider] Setting up player with URL: \(url)")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            showError("视频文件不存在")
            return
        }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Create queue player for looping
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = true // Mute by default for PiP

        // Important: Allow playback when the app is in background
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false

        // Create looper
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

        // Create player layer
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = contentView.bounds

        contentView.layer.insertSublayer(layer, at: 0)

        self.player = queuePlayer
        self.playerLooper = looper
        self._playerLayer = layer

        // Hide placeholder
        placeholderLabel.isHidden = true

        // Start playing
        queuePlayer.play()

        print("[VideoLoopProvider] Player started")
    }

    private func cleanupPlayer() {
        player?.pause()
        playerLooper?.disableLooping()
        _playerLayer?.removeFromSuperlayer()
        _playerLayer = nil
        playerLooper = nil
        player = nil
    }

    private func removeAllObservers() {
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }
        if let observer = appWillResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appWillResignActiveObserver = nil
        }
        if let observer = appDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidEnterBackgroundObserver = nil
        }
        if let observer = playerItemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemDidPlayToEndObserver = nil
        }
    }

    private func setupAppLifecycleHandling() {
        // Resume playback when app becomes active
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[VideoLoopProvider] App became active, resuming playback...")
                self.player?.play()
            }
        }

        // Keep playing when app resigns active (e.g., control center appears)
        appWillResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[VideoLoopProvider] App will resign active, ensuring playback continues...")
                self.player?.play()
            }
        }

        // Keep playing when app enters background
        appDidEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                print("[VideoLoopProvider] App entered background, ensuring playback continues...")
                self.player?.play()
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
            // Use playback category to allow background audio
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
            print("[VideoLoopProvider] Audio session configured for background playback")
        } catch {
            print("[VideoLoopProvider] Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Persistence

    private func saveVideoURL(_ url: URL) {
        // For security, we need to create a bookmark for the URL
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Self.videoURLKey)
            print("[VideoLoopProvider] Video URL saved")
        } catch {
            print("[VideoLoopProvider] Failed to save video URL: \(error)")
        }
    }

    private func loadSavedVideoURL() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.videoURLKey) else {
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, try to refresh
                saveVideoURL(url)
            }

            self.videoURL = url
            print("[VideoLoopProvider] Loaded saved video URL: \(url)")
        } catch {
            print("[VideoLoopProvider] Failed to load saved video URL: \(error)")
            // Clear invalid bookmark
            UserDefaults.standard.removeObject(forKey: Self.videoURLKey)
        }
    }

    // MARK: - Celebration

    private func setupCelebrationObserver() {
        print("[VideoLoopProvider] Setting up celebration observer")

        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .dropFirst()
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                print("[VideoLoopProvider] Received away interval: \(interval.duration) seconds")
                self?.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)

        print("[VideoLoopProvider] Celebration observer setup complete")
    }

    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true

        print("[VideoLoopProvider] Showing celebration for \(Int(duration)) seconds away")

        // Pause video during celebration
        player?.pause()
        _playerLayer?.isHidden = true
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

        print("[VideoLoopProvider] Celebration view added")
    }

    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false

        // Resume video playback
        _playerLayer?.isHidden = false
        player?.play()

        DisplayTimeTracker.shared.clearLastAwayInterval()

        print("[VideoLoopProvider] Celebration ended")
    }
}

// MARK: - VideoContainerView

/// A custom UIView that automatically updates its player layer frame when bounds change.
private class VideoContainerView: UIView {

    override func layoutSubviews() {
        super.layoutSubviews()

        // Update all CALayer sublayers that are AVPlayerLayer
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                if let playerLayer = sublayer as? AVPlayerLayer {
                    playerLayer.frame = bounds
                }
            }
        }
    }
}
