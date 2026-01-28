//
//  CatCompanionProvider.swift
//  Porthole
//
//  Provides an animated companion cat (BongoCat style) for PiP display.
//

import UIKit
import SpriteKit

/// A content provider that displays an animated companion cat in PiP window using SpriteKit.
@MainActor
final class CatCompanionProvider: PiPContentProvider {

    // MARK: - PiPContentProvider Static Properties

    static let providerType: String = "cat"
    static let displayName: String = "小猫"
    static let iconName: String = "cat.fill"

    // MARK: - PiPContentProvider

    let contentView: UIView // This will hold our SKView
    let preferredFrameRate: Int = 30 // Higher frame rate for smooth SpriteKit animation

    // MARK: - Private Properties

    private let skView: SKView
    private let catScene: CatScene
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    init() {
        // Create container view with fixed size
        let containerSize = CGSize(width: 200, height: 100)

        // Setup SKView
        skView = SKView(frame: CGRect(origin: .zero, size: containerSize))
        skView.backgroundColor = .white
        skView.ignoresSiblingOrder = true
        // skView.showsFPS = true // Debug

        // Setup Scene
        catScene = CatScene(size: containerSize)
        catScene.scaleMode = .aspectFill

        self.contentView = skView

        print("[CatCompanionProvider] Initialized with SKView")

        // Observe app lifecycle to keep animation running in PiP
        setupNotifications()
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
            // Keep the SKView running when app goes to background
            // This is essential for PiP to continue showing the animation
            self?.skView.isPaused = false
            print("[CatCompanionProvider] App will resign active - keeping SKView running")
        }
        notificationObservers.append(resignObserver)

        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Ensure SKView stays unpaused in background for PiP
            self?.skView.isPaused = false
            print("[CatCompanionProvider] App entered background - ensuring SKView is not paused")
        }
        notificationObservers.append(backgroundObserver)
    }

    // MARK: - PiPContentProvider Methods

    func start() {
        print("[CatCompanionProvider] start()")

        // Ensure SKView is not paused
        skView.isPaused = false

        // Present the scene
        if skView.scene == nil {
            skView.presentScene(catScene)
        }

        // Start animation in scene
        catScene.startBongoAnimation()
    }

    func stop() {
        print("[CatCompanionProvider] stop()")

        // Stop animation
        catScene.stopAnimation()

        // Note: Do NOT pause skView here.
        // When in PiP mode, the SKView continues to run inside the PiP window.
        // Pausing it would freeze the animation in the PiP window.
    }
}
