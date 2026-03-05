//
//  TimerProvider.swift
//  Porthole
//
//  Provides a timer view for PiP display that auto-starts on launch.
//  Optimized with TextHardwareRenderer for minimal CPU usage.
//

import UIKit
import AVFoundation
import Combine

/// A content provider that displays an elapsed time timer in PiP window.
/// Timer automatically starts when PiP is launched and can be paused/resumed.
/// Uses TextHardwareRenderer for efficient direct rendering to pixel buffer.
@MainActor
final class TimerProvider: NSObject, DirectVideoProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "timer"
    static let displayName: String = "计时器"
    static let iconName: String = "timer"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 1
    
    // MARK: - DirectVideoProvider
    
    private var outputLayer: AVSampleBufferDisplayLayer?
    
    // MARK: - Private Properties

    private var renderer: TextHardwareRenderer?
    private let placeholderLabel: UILabel
    private var elapsedSeconds: TimeInterval = 0
    private var isPaused = false
    private var countingTimer: Timer?
    
    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false
    private var lastCelebratedIntervalId: UUID?
    
    // MARK: - Initialization
    
    override init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black

        // Create placeholder label
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = UIColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)
        label.textAlignment = .center
        label.text = "00:00:00"
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

        print("[TimerProvider] Initialized with DirectVideoProvider support")
    }
    
    // MARK: - DirectVideoProvider Methods
    
    func setOutputLayer(_ layer: AVSampleBufferDisplayLayer) {
        print("[TimerProvider] setOutputLayer called")
        self.outputLayer = layer
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[TimerProvider] start() - isPaused: \(isPaused)")

        // If fresh start, reset elapsed time
        if !isPaused {
            elapsedSeconds = 0
        }
        isPaused = false
        
        // Hide placeholder
        placeholderLabel.isHidden = true
        
        // Create hardware renderer
        guard let layer = outputLayer else {
            print("[TimerProvider] ERROR: No output layer set")
            placeholderLabel.text = "显示层未初始化"
            placeholderLabel.isHidden = false
            return
        }
        
        renderer = TextHardwareRenderer(displayLayer: layer)
        renderer?.configure(
            font: UIFont.monospacedDigitSystemFont(ofSize: 72, weight: .semibold),
            textColor: UIColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0),
            backgroundColor: .black
        )
        renderer?.setFrameRate(preferredFrameRate)
        
        // Provide text generator
        renderer?.textProvider = { [weak self] in
            guard let self = self, !self.isCelebrating else { return "" }
            return self.formatTime(self.elapsedSeconds)
        }
        
        renderer?.start()
        
        // Start counting timer (separate from rendering)
        startCountingTimer()

        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()
    }
    
    func stop() {
        print("[TimerProvider] stop()")
        isPaused = true
        countingTimer?.invalidate()
        countingTimer = nil
        renderer?.stop()
        renderer = nil
        cancellables.removeAll()
        removeCelebration()
    }
    
    // MARK: - Public Methods
    
    /// Resets the timer to zero
    func reset() {
        elapsedSeconds = 0
    }
    
    /// Returns current elapsed time
    var currentElapsedTime: TimeInterval {
        return elapsedSeconds
    }
    
    // MARK: - Private Methods
    
    private func startCountingTimer() {
        countingTimer?.invalidate()
        countingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused, !self.isCelebrating else { return }
            self.elapsedSeconds += 1
        }
        
        if let timer = countingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    // MARK: - Celebration
    
    private func setupCelebrationObserver() {
        print("[TimerProvider] Setting up celebration observer")
        
        cancellables.removeAll()
        
        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let self = self else { return }
                guard self.lastCelebratedIntervalId != interval.id else { return }
                self.lastCelebratedIntervalId = interval.id
                print("[TimerProvider] Received away interval: \(interval.duration) seconds")
                self.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)
        
        print("[TimerProvider] Celebration observer setup complete")
    }
    
    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true
        
        print("[TimerProvider] Showing celebration for \(Int(duration)) seconds away")
        
        // Increase frame rate for smooth animation
        renderer?.setFrameRate(30)

        // Create and show celebration view
        let celebration = CelebrationView(frame: contentView.bounds)
        celebration.awayDuration = duration
        celebration.onComplete = { [weak self] in
            self?.removeCelebration()
        }
        
        contentView.addSubview(celebration)
        celebrationView = celebration
        
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        
        celebration.startCelebration()
        
        print("[TimerProvider] Celebration view added, frame: \(celebration.frame)")
    }
    
    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false

        // Restore normal frame rate
        renderer?.setFrameRate(preferredFrameRate)
        DisplayTimeTracker.shared.clearLastAwayInterval()

        print("[TimerProvider] Celebration ended")
    }
}
