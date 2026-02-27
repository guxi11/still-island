//
//  CatScene.swift
//  Porthole
//
//  A SpriteKit scene that renders a running cat using a Sprite Sheet.
//  Includes cropping logic to remove frame numbers or extra padding.
//

import SpriteKit

class CatScene: SKScene {

    // MARK: - Configuration

    // Sprite sheet layout: 2x2 grid (田字格)
    private let columns = 2
    private let rows = 2

    // Playback speed (seconds per frame)
    private let timePerFrame = 0.15

    // MARK: - Nodes

    private var catNode: SKSpriteNode?
    
    // MARK: - State
    
    private var textures: [SKTexture] = []
    
    // MARK: - Initialization

    override func didMove(to view: SKView) {
        backgroundColor = .white
        scaleMode = .resizeFill

        setupSceneIfNeeded()
    }

    // MARK: - Setup

    private func setupSceneIfNeeded() {
        guard textures.isEmpty else { return }
        loadTextures()
        setupScene()
    }

    private func loadTextures() {
        textures = []

        // Try to load sprite sheet: "cat_sprites"
        if let spriteSheet = UIImage(named: "cat_sprites") {
            print("[CatScene] Found sprite sheet 'cat_sprites'. Processing as \(columns)x\(rows) grid...")
            let sheetTexture = SKTexture(image: spriteSheet)
            sheetTexture.filteringMode = .nearest

            let frameWidth = 1.0 / CGFloat(columns)
            let frameHeight = 1.0 / CGFloat(rows)

            // Read frames in order: top-left, top-right, bottom-left, bottom-right
            // SpriteKit texture coords: Y=0 is bottom, Y=1 is top
            // So row 0 (top) has yOrigin = 1 - frameHeight = 0.5
            //    row 1 (bottom) has yOrigin = 0
            for row in 0..<rows {
                for col in 0..<columns {
                    let xOrigin = CGFloat(col) * frameWidth
                    // Flip Y: top row first
                    let yOrigin = 1.0 - CGFloat(row + 1) * frameHeight

                    let rect = CGRect(x: xOrigin, y: yOrigin, width: frameWidth, height: frameHeight)
                    let frameTexture = SKTexture(rect: rect, in: sheetTexture)
                    frameTexture.filteringMode = .nearest
                    textures.append(frameTexture)
                    print("[CatScene] Frame \(textures.count - 1): rect = \(rect)")
                }
            }
            return
        }

        // Fallback: Try individual frames
        var index = 0
        while true {
            let name = "cat_run_\(index)"
            if UIImage(named: name) != nil {
                let texture = SKTexture(imageNamed: name)
                texture.filteringMode = .nearest
                textures.append(texture)
                index += 1
            } else {
                break
            }
        }

        if !textures.isEmpty {
            print("[CatScene] Found \(textures.count) individual frame images")
        }
    }
    
    private func setupScene() {
        removeAllChildren()
        
        let node: SKSpriteNode
        if !textures.isEmpty {
            node = SKSpriteNode(texture: textures[0])
            // Scale to fit within scene bounds while maintaining aspect ratio
            let textureSize = textures[0].size()
            let maxScale = min(size.width / textureSize.width, size.height / textureSize.height) * 0.8
            node.setScale(maxScale)
        } else {
            // Placeholder
            node = SKSpriteNode(color: .orange, size: CGSize(width: 60, height: 40))
            let label = SKLabelNode(text: "No 'cat_sprites'")
            label.fontSize = 8
            label.fontColor = .black
            label.position = CGPoint(x: 0, y: -5)
            node.addChild(label)
            print("[CatScene] No textures found. Please add 'cat_sprites' to Assets.")
        }
        
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(node)
        catNode = node
        
        startBongoAnimation()
    }
    
    // MARK: - Animation

    func startBongoAnimation() {
        // Ensure scene is set up before starting animation
        setupSceneIfNeeded()

        guard !textures.isEmpty, let node = catNode else { return }

        node.removeAction(forKey: "run")

        let animate = SKAction.animate(with: textures, timePerFrame: timePerFrame)
        let forever = SKAction.repeatForever(animate)

        node.run(forever, withKey: "run")
    }
    
    func stopAnimation() {
        catNode?.removeAction(forKey: "run")
    }
}
