//
//  TimerProvider.swift
//  Porthole
//
//  Provides a timer view for PiP display that auto-starts on launch.
//

import UIKit
import Combine

/// A content provider that displays an elapsed time timer in PiP window.
/// Timer automatically starts when PiP is launched and can be paused/resumed.
@MainActor
final class TimerProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "timer"
    static let displayName: String = "计时器"
    static let iconName: String = "timer"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 1
    
    // MARK: - Private Properties

    private let timerLabel: UILabel
    private var timer: Timer?
    private var elapsedSeconds: TimeInterval = 0
    private var isPaused = false
    
    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false
    
    // MARK: - Initialization
    
    init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0) // Slightly green tint

        // Create timer label with Auto Layout for proper centering
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = UIColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0) // Green color for timer
        label.textAlignment = .center
        label.text = "00:00:00"
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)

        // Setup constraints for centering
        NSLayoutConstraint.activate([
            // Timer label: centered both horizontally and vertically
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])

        self.contentView = container
        self.timerLabel = label

        // Force layout
        container.setNeedsLayout()
        container.layoutIfNeeded()

        print("[TimerProvider] Initialized with view size: \(container.bounds.size)")
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[TimerProvider] start() - isPaused: \(isPaused)")

        // If resuming from pause, just continue
        // If fresh start, reset elapsed time
        if !isPaused {
            elapsedSeconds = 0
        }
        isPaused = false

        // Update display immediately
        updateDisplay()

        // Start timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.elapsedSeconds += 1
            self.updateDisplay()
        }

        // Add to common run loop mode for background operation
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()
    }
    
    func stop() {
        print("[TimerProvider] stop()")
        isPaused = true
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        removeCelebration()
    }
    
    // MARK: - Public Methods
    
    /// Resets the timer to zero
    func reset() {
        elapsedSeconds = 0
        updateDisplay()
    }
    
    /// Returns current elapsed time
    var currentElapsedTime: TimeInterval {
        return elapsedSeconds
    }
    
    // MARK: - Private Methods
    
    private func updateDisplay() {
        // Don't update timer label during celebration
        guard !isCelebrating else { return }
        
        let totalSeconds = Int(elapsedSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        timerLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Force redraw
        contentView.setNeedsDisplay()
        timerLabel.setNeedsDisplay()
    }

    // MARK: - Celebration
    
    private func setupCelebrationObserver() {
        print("[TimerProvider] Setting up celebration observer")
        
        // Subscribe to away interval completion
        // Using dropFirst to ignore initial nil value
        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .dropFirst()  // Skip initial nil
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                print("[TimerProvider] Received away interval: \(interval.duration) seconds")
                self?.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)
        
        print("[TimerProvider] Celebration observer setup complete")
    }
    
    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true
        
        print("[TimerProvider] Showing celebration for \(Int(duration)) seconds away")
        
        // Increase frame rate for smooth animation
        PiPManager.shared.setFrameRate(30)

        // Hide timer label
        timerLabel.isHidden = true

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
        
        print("[TimerProvider] Celebration view added, frame: \(celebration.frame)")
    }
    
    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false

        // Show timer label again
        timerLabel.isHidden = false

        // Restore normal frame rate
        PiPManager.shared.setFrameRate(preferredFrameRate)
        DisplayTimeTracker.shared.clearLastAwayInterval()

        print("[TimerProvider] Celebration ended")
    }
}
