//
//  TimeDisplayProvider.swift
//  Still Island
//
//  Provides a digital clock view for PiP display.
//

import UIKit

/// A content provider that displays a digital clock in PiP window.
/// Shows current time in HH:mm:ss format with high contrast styling.
final class TimeDisplayProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 10
    
    // MARK: - Private Properties
    
    private let timeLabel: UILabel
    private var timer: Timer?
    private let dateFormatter: DateFormatter
    
    // MARK: - Initialization
    
    init() {
        // Configure date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        // Create time label with manual frame layout (Auto Layout doesn't work well off-screen)
        let label = UILabel(frame: container.bounds)
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.text = dateFormatter.string(from: Date())
        label.backgroundColor = .clear
        
        container.addSubview(label)
        
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
    }
    
    func stop() {
        print("[TimeDisplayProvider] stop()")
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Private Methods
    
    private func updateTime() {
        let timeString = dateFormatter.string(from: Date())
        timeLabel.text = timeString
        
        // Force redraw
        contentView.setNeedsDisplay()
        timeLabel.setNeedsDisplay()
    }
}
