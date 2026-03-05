//
//  TimeDisplayProvider.swift
//  Porthole
//
//  Provides a digital clock view for PiP display.
//  Optimized with TextHardwareRenderer for minimal CPU usage.
//

import UIKit
import AVFoundation
import Combine

/// A content provider that displays a digital clock in PiP window.
/// Shows current time in HH:mm:ss format with high contrast styling.
/// Uses TextHardwareRenderer for efficient direct rendering to pixel buffer.
@MainActor
final class TimeDisplayProvider: NSObject, DirectVideoProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "time"
    static let displayName: String = "时钟"
    static let iconName: String = "clock.fill"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 1
    
    // MARK: - DirectVideoProvider
    
    private var outputLayer: AVSampleBufferDisplayLayer?
    
    // MARK: - Private Properties
    
    private var renderer: TextHardwareRenderer?
    private let dateFormatter: DateFormatter
    private let placeholderLabel: UILabel
    
    // Celebration
    private var celebrationView: CelebrationView?
    private var cancellables = Set<AnyCancellable>()
    private var isCelebrating = false
    private var lastCelebratedIntervalId: UUID?
    
    // MARK: - Initialization
    
    override init() {
        // Configure date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        container.backgroundColor = UIColor.black
        
        // Create placeholder label (shown during loading)
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.text = dateFormatter.string(from: Date())
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
        
        print("[TimeDisplayProvider] Initialized with DirectVideoProvider support")
    }
    
    // MARK: - DirectVideoProvider Methods
    
    func setOutputLayer(_ layer: AVSampleBufferDisplayLayer) {
        print("[TimeDisplayProvider] setOutputLayer called")
        self.outputLayer = layer
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[TimeDisplayProvider] start()")
        
        // Hide placeholder
        placeholderLabel.isHidden = true
        
        // Create hardware renderer
        guard let layer = outputLayer else {
            print("[TimeDisplayProvider] ERROR: No output layer set")
            placeholderLabel.text = "显示层未初始化"
            placeholderLabel.isHidden = false
            return
        }
        
        renderer = TextHardwareRenderer(displayLayer: layer)
        renderer?.configure(
            font: UIFont.monospacedDigitSystemFont(ofSize: 72, weight: .semibold),
            textColor: .white,
            backgroundColor: .black
        )
        renderer?.setFrameRate(preferredFrameRate)
        
        // Provide text generator
        renderer?.textProvider = { [weak self] in
            guard let self = self, !self.isCelebrating else { return "" }
            return self.dateFormatter.string(from: Date())
        }
        
        renderer?.start()
        
        // Subscribe to away interval completion for celebration
        setupCelebrationObserver()
    }
    
    func stop() {
        print("[TimeDisplayProvider] stop()")
        renderer?.stop()
        renderer = nil
        cancellables.removeAll()
        removeCelebration()
    }
    
    // MARK: - Celebration
    
    private func setupCelebrationObserver() {
        print("[TimeDisplayProvider] Setting up celebration observer")
        
        cancellables.removeAll()
        
        DisplayTimeTracker.shared.$lastCompletedAwayInterval
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let self = self else { return }
                guard self.lastCelebratedIntervalId != interval.id else { return }
                self.lastCelebratedIntervalId = interval.id
                print("[TimeDisplayProvider] Received away interval: \(interval.duration) seconds")
                self.showCelebration(duration: interval.duration)
            }
            .store(in: &cancellables)
        
        print("[TimeDisplayProvider] Celebration observer setup complete")
    }
    
    private func showCelebration(duration: TimeInterval) {
        guard !isCelebrating else { return }
        isCelebrating = true
        
        print("[TimeDisplayProvider] Showing celebration for \(Int(duration)) seconds away")
        
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
        
        print("[TimeDisplayProvider] Celebration view added, frame: \(celebration.frame)")
    }
    
    private func removeCelebration() {
        celebrationView?.removeFromSuperview()
        celebrationView = nil
        isCelebrating = false
        
        // Restore normal frame rate
        renderer?.setFrameRate(preferredFrameRate)
        DisplayTimeTracker.shared.clearLastAwayInterval()
        
        print("[TimeDisplayProvider] Celebration ended")
    }
}
