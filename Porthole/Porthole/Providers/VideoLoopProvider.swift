//
//  VideoLoopProvider.swift
//  Porthole
//
//  Provides looping video playback for PiP display using SpriteKit.
//  Uses the same technique as CatCompanionProvider for consistent PiP behavior.
//

import UIKit
import AVFoundation

/// A content provider that plays video in a loop for PiP window using SpriteKit.
/// This approach is identical to CatCompanionProvider for reliable PiP support.
@MainActor
final class VideoLoopProvider: NSObject, DirectVideoProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "video"
    static let displayName: String = "视频"
    static let iconName: String = "play.rectangle.fill"

    // MARK: - PiPContentProvider Properties

    let contentView: UIView  // Container view for placeholder
    let preferredFrameRate: Int = 30
    
    // MARK: - DirectVideoProvider
    
    /// The output layer set by PiPManager for direct video output
    private var outputLayer: AVSampleBufferDisplayLayer?

    // MARK: - Private Properties

    private var renderer: VideoHardwareRenderer?
    private let placeholderLabel: UILabel
    private var isRunning = false

    // MARK: - Public Properties

    /// The currently selected video URL
    private(set) var videoURL: URL?

    /// Callback when video selection is needed
    var onNeedVideoSelection: (() -> Void)?

    // MARK: - Initialization

    override init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = .black

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

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])

        self.contentView = container
        self.placeholderLabel = label

        super.init()

        print("[VideoLoopProvider] Initialized with DirectVideoProvider support")
    }
    
    deinit {
        renderer?.stop()
    }
    
    // MARK: - DirectVideoProvider Methods
    
    func setOutputLayer(_ layer: AVSampleBufferDisplayLayer) {
        print("[VideoLoopProvider] setOutputLayer called")
        self.outputLayer = layer
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[VideoLoopProvider] start()")

        guard !isRunning else { return }
        isRunning = true

        // Configure audio session
        configureAudioSession()

        // Start renderer if URL is set and output layer is available
        if let url = videoURL, let layer = outputLayer {
            placeholderLabel.isHidden = true
            renderer = VideoHardwareRenderer(videoURL: url, displayLayer: layer)
            renderer?.start()
        } else if videoURL == nil {
            placeholderLabel.text = "未选择视频"
            placeholderLabel.isHidden = false
        } else {
            placeholderLabel.text = "显示层未初始化"
            placeholderLabel.isHidden = false
        }
    }

    func stop() {
        print("[VideoLoopProvider] stop()")
        isRunning = false
        renderer?.stop()
        renderer = nil
    }

    // MARK: - Public Methods

    /// Set the video URL (persistence is handled by CardManager)
    func setVideoURL(_ url: URL) {
        print("[VideoLoopProvider] Setting video URL: \(url)")
        self.videoURL = url

        if isRunning, let layer = outputLayer {
            // Recreate renderer with new URL
            renderer?.stop()
            renderer = VideoHardwareRenderer(videoURL: url, displayLayer: layer)
            renderer?.start()
            placeholderLabel.isHidden = true
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
