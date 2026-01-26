//
//  TimerProvider.swift
//  Still Island
//
//  Provides a timer view for PiP display that auto-starts on launch.
//

import UIKit

/// A content provider that displays an elapsed time timer in PiP window.
/// Timer automatically starts when PiP is launched and can be paused/resumed.
final class TimerProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "timer"
    static let displayName: String = "计时器"
    static let iconName: String = "timer"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 10
    
    // MARK: - Private Properties
    
    private let timerLabel: UILabel
    private let subtitleLabel: UILabel
    private var timer: Timer?
    private var elapsedSeconds: TimeInterval = 0
    private var isPaused = false
    
    // MARK: - Initialization
    
    init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0) // Slightly green tint
        
        // Create timer label
        let label = UILabel(frame: CGRect(x: 0, y: 15, width: containerSize.width, height: 50))
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = UIColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0) // Green color for timer
        label.textAlignment = .center
        label.text = "00:00:00"
        label.backgroundColor = .clear
        
        // Create subtitle label
        let subtitle = UILabel(frame: CGRect(x: 0, y: 65, width: containerSize.width, height: 20))
        subtitle.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.6)
        subtitle.textAlignment = .center
        subtitle.text = "计时中"
        subtitle.backgroundColor = .clear
        
        container.addSubview(label)
        container.addSubview(subtitle)
        
        self.contentView = container
        self.timerLabel = label
        self.subtitleLabel = subtitle
        
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
        updateSubtitle()
        
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
    }
    
    func stop() {
        print("[TimerProvider] stop()")
        isPaused = true
        timer?.invalidate()
        timer = nil
        updateSubtitle()
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
        let totalSeconds = Int(elapsedSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        timerLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Force redraw
        contentView.setNeedsDisplay()
        timerLabel.setNeedsDisplay()
    }
    
    private func updateSubtitle() {
        subtitleLabel.text = isPaused ? "已暂停" : "计时中"
        subtitleLabel.textColor = isPaused 
            ? UIColor.orange.withAlphaComponent(0.8) 
            : UIColor.white.withAlphaComponent(0.6)
    }
}
