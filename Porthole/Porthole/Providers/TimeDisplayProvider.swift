//
//  TimeDisplayProvider.swift
//  Porthole
//
//  Provides a digital clock view for PiP display.
//

import UIKit
import Combine

/// A content provider that displays a digital clock in PiP window.
/// Shows current time in HH:mm:ss format with high contrast styling.
@MainActor
final class TimeDisplayProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "time"
    static let displayName: String = "时钟"
    static let iconName: String = "clock.fill"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 10
    
    // MARK: - Private Properties
    
    private let timeLabel: UILabel
    private var timer: Timer?
    private let dateFormatter: DateFormatter
    
    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false
    
    // MARK: - Initialization
    
    init() {
        // Configure date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        // Create time label with Auto Layout for proper centering
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.text = dateFormatter.string(from: Date())
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        
        // Setup constraints for centering
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])
        
        self.contentView = container
        self.timeLabel = label
        
        // Force layout
        container.setNeedsLayout()
        container.layoutIfNeeded()
        
        print("[TimeDisplayProvider] Initialized with view size: \(container.bounds.size), label: \(label.text ?? "nil")")
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[TimeDisplayProvider] start()")
        
        // Update immediately
        updateTime()
        
        // Start timer for updates
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
        
        // Add to common run loop mode for background operation
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()
    }
    
    func stop() {
        print("[TimeDisplayProvider] stop()")
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        removeCelebration()
    }
    
    // MARK: - Private Methods
    
    private func updateTime() {
        // Don't update time label during celebration
        guard !isCelebrating else { return }
        
        let timeString = dateFormatter.string(from: Date())
        timeLabel.text = timeString
        
        // Force redraw
        contentView.setNeedsDisplay()
        timeLabel.setNeedsDisplay()
    }
    
    // MARK: - Celebration
    
    private func setupCelebrationObserver() {
        print("[TimeDisplayProvider] Setting up celebration observer")
        
        // Subscribe to away interval completion
        // Using dropFirst to ignore initial nil value
        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .dropFirst()  // Skip initial nil
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                print("[TimeDisplayProvider] Received away interval: \(interval.duration) seconds")
                self?.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)
        
        print("[TimeDisplayProvider] Celebration observer setup complete")
    }
    
    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true
        
        print("[TimeDisplayProvider] Showing celebration for \(Int(duration)) seconds away")
        
        // Increase frame rate for smooth animation
        PiPManager.shared.setFrameRate(30)
        
        // Hide time label
        timeLabel.isHidden = true
        
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
        
        print("[TimeDisplayProvider] Celebration view added, frame: \(celebration.frame)")
    }
    
    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false
        
        // Show time label again
        timeLabel.isHidden = false
        
        // Restore normal frame rate
        PiPManager.shared.setFrameRate(preferredFrameRate)
        DisplayTimeTracker.shared.clearLastAwayInterval()
        
        print("[TimeDisplayProvider] Celebration ended")
    }
}
