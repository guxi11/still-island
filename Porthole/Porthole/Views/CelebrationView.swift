//
//  CelebrationView.swift
//  Porthole
//
//  Celebration view with confetti effects shown when user returns from being away.
//

import UIKit

/// A UIView that displays a celebration animation with confetti (triangles/rectangles)
/// when the user returns after being away from their phone.
final class CelebrationView: UIView {
    
    // MARK: - Properties
    
    private var emitterLayer: CAEmitterLayer?
    private var topLabel: UILabel!
    private var durationLabel: UILabel!
    private var bottomLabel: UILabel!
    private var containerView: UIView!
    
    /// Duration the user was away (in seconds)
    var awayDuration: TimeInterval = 0 {
        didSet { updateLabels() }
    }
    
    /// Callback when celebration animation completes
    var onComplete: (() -> Void)?
    
    // Confetti colors - bright, festive firework-like colors
    private let confettiColors: [UIColor] = [
        UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0),  // Red
        UIColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1.0),   // Gold
        UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),    // Yellow
        UIColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1.0),    // Green
        UIColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 1.0),   // Blue
        UIColor(red: 0.85, green: 0.5, blue: 1.0, alpha: 1.0),   // Purple
        UIColor(red: 1.0, green: 0.5, blue: 0.75, alpha: 1.0),   // Pink
        UIColor.white,                                            // White sparkle
    ]
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        
        // Container for text
        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        // Top label
        topLabel = UILabel()
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.textAlignment = .center
        topLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        topLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        topLabel.alpha = 0
        topLabel.text = "你已经熄屏"
        containerView.addSubview(topLabel)
        
        // Duration label (main text showing time away)
        durationLabel = UILabel()
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.textAlignment = .center
        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.alpha = 0
        containerView.addSubview(durationLabel)
        
        // Bottom label
        bottomLabel = UILabel()
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomLabel.textAlignment = .center
        bottomLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        bottomLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        bottomLabel.alpha = 0
        bottomLabel.text = "恭喜你"
        containerView.addSubview(bottomLabel)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: widthAnchor),
            
            topLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            topLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            
            durationLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            durationLabel.topAnchor.constraint(equalTo: topLabel.bottomAnchor, constant: 6),
            
            bottomLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            bottomLabel.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 6),
            bottomLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update emitter position when bounds change
        if let emitter = emitterLayer {
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
            emitter.emitterSize = CGSize(width: bounds.width * 1.5, height: 1)
        }
    }
    
    // MARK: - Public Methods
    
    /// Start the celebration animation
    func startCelebration() {
        // Start immediately with a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // Setup and start confetti emitter
            self.setupConfettiEmitter()
            
            // Animate labels in
            self.animateLabelsIn()
        }
        
        // Stop emitting after 3s (but existing particles continue falling)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.emitterLayer?.birthRate = 0
        }
        
        // Schedule end of celebration (total 5s - gives user time to unlock and see it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.endCelebration()
        }
    }
    
    /// End the celebration animation
    func endCelebration() {
        // Stop emitting new confetti
        emitterLayer?.birthRate = 0
        
        // Fade out after confetti falls
        UIView.animate(withDuration: 0.3, delay: 0) { [weak self] in
            self?.emitterLayer?.opacity = 0
        }
        
        // Fade out labels
        UIView.animate(withDuration: 0.25, delay: 0) { [weak self] in
            self?.topLabel.alpha = 0
            self?.durationLabel.alpha = 0
            self?.bottomLabel.alpha = 0
        } completion: { [weak self] _ in
            self?.emitterLayer?.removeFromSuperlayer()
            self?.emitterLayer = nil
            self?.onComplete?()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateLabels() {
        durationLabel.text = formatDuration(awayDuration)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // Setup confetti emitter - burst style like fireworks
    private func setupConfettiEmitter() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: bounds.width * 1.5, height: 1)
        
        var cells: [CAEmitterCell] = []
        
        // Create confetti cells with different shapes and colors
        for color in confettiColors {
            // Small circle sparks (like firework sparks)
            let sparkCell = createConfettiCell(
                shape: .circle,
                color: color,
                birthRate: 6,
                scale: 0.08
            )
            cells.append(sparkCell)
            
            // Triangle confetti
            let triangleCell = createConfettiCell(
                shape: .triangle,
                color: color,
                birthRate: 3,
                scale: 0.1
            )
            cells.append(triangleCell)
            
            // Rectangle confetti (like ribbon pieces)
            let rectangleCell = createConfettiCell(
                shape: .rectangle,
                color: color,
                birthRate: 2,
                scale: 0.08
            )
            cells.append(rectangleCell)
        }
        
        emitter.emitterCells = cells
        layer.insertSublayer(emitter, at: 0)
        emitterLayer = emitter
    }
    
    private enum ConfettiShape {
        case triangle
        case rectangle
        case circle
    }
    
    private func createConfettiCell(
        shape: ConfettiShape,
        color: UIColor,
        birthRate: Float,
        scale: CGFloat
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        
        // Create shape image
        switch shape {
        case .triangle:
            cell.contents = createTriangleImage(size: CGSize(width: 10, height: 10), color: color)
        case .rectangle:
            cell.contents = createRectangleImage(size: CGSize(width: 6, height: 12), color: color)
        case .circle:
            cell.contents = createCircleImage(size: CGSize(width: 8, height: 8), color: color)
        }
        
        cell.birthRate = birthRate
        cell.lifetime = 2.0
        cell.lifetimeRange = 0.5
        
        // Falling velocity - faster initial burst
        cell.velocity = 120
        cell.velocityRange = 60
        
        cell.emissionLongitude = .pi  // Downward
        cell.emissionRange = .pi / 4  // Wider spread for burst effect
        
        // Add horizontal drift for natural movement
        cell.xAcceleration = 0
        cell.yAcceleration = 50  // Gravity effect
        
        cell.scale = scale
        cell.scaleRange = scale * 0.4
        cell.scaleSpeed = -0.02  // Slightly shrink as they fall
        
        // Spinning animation
        cell.spin = .pi * 2
        cell.spinRange = .pi * 3
        
        // Fade out as they fall
        cell.alphaSpeed = -0.4
        
        return cell
    }
    
    // Create a triangle image
    private func createTriangleImage(size: CGSize, color: UIColor) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(color.cgColor)
        
        // Draw triangle
        context.move(to: CGPoint(x: size.width / 2, y: 0))
        context.addLine(to: CGPoint(x: size.width, y: size.height))
        context.addLine(to: CGPoint(x: 0, y: size.height))
        context.closePath()
        context.fillPath()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image?.cgImage
    }
    
    // Create a rectangle image (ribbon-like)
    private func createRectangleImage(size: CGSize, color: UIColor) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image?.cgImage
    }
    
    // Create a circle image (spark-like)
    private func createCircleImage(size: CGSize, color: UIColor) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image?.cgImage
    }
    
    private func animateLabelsIn() {
        // Fade in top label first
        UIView.animate(withDuration: 0.25, delay: 0) { [weak self] in
            self?.topLabel.alpha = 1
        }
        
        // Scale and fade in duration label
        durationLabel.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(
            withDuration: 0.4,
            delay: 0.1,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8
        ) { [weak self] in
            self?.durationLabel.alpha = 1
            self?.durationLabel.transform = .identity
        }
        
        // Fade in bottom label last
        UIView.animate(withDuration: 0.25, delay: 0.25) { [weak self] in
            self?.bottomLabel.alpha = 1
        }
    }
}
