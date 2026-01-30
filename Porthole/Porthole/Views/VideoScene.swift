//
//  VideoScene.swift
//  Porthole
//
//  A SpriteKit scene that plays video frames in a loop.
//  Uses the same technique as CatScene for consistent PiP behavior.
//

import SpriteKit
import AVFoundation

class VideoScene: SKScene {
    
    // MARK: - Configuration
    
    // Target frame rate for extraction (higher = smoother but more memory)
    private let targetFPS: Double = 24
    
    // Maximum frames to extract (memory limit)
    private let maxFrames: Int = 480  // ~20 seconds at 24fps
    
    // MARK: - Nodes
    
    private var videoNode: SKSpriteNode?
    
    // MARK: - State
    
    private var textures: [SKTexture] = []
    private var isLoaded = false
    private var isAnimating = false
    private var videoURL: URL?
    private var timePerFrame: TimeInterval = 1.0 / 15.0
    private var videoAspectRatio: CGFloat = 16.0 / 9.0  // Default aspect ratio
    
    // Loading state callback
    var onLoadingStateChanged: ((Bool, String?) -> Void)?
    
    // MARK: - Initialization
    
    override func didMove(to view: SKView) {
        backgroundColor = .black
        scaleMode = .resizeFill
        
        setupPlaceholder()
    }
    
    // MARK: - Setup
    
    private func setupPlaceholder() {
        let node = SKSpriteNode(color: .darkGray, size: size)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(node)
        videoNode = node
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Update node position and size when scene resizes
        updateVideoNodeLayout()
    }
    
    /// Update video node to fill scene (AspectFill/Cover mode - may crop)
    private func updateVideoNodeLayout() {
        guard let node = videoNode else { return }
        
        // Center the node
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        
        // Calculate size that fills entire scene while maintaining aspect ratio (Cover/AspectFill)
        let sceneAspect = size.width / size.height
        
        var nodeWidth: CGFloat
        var nodeHeight: CGFloat
        
        if videoAspectRatio > sceneAspect {
            // Video is wider than scene - fit to height (crop sides)
            nodeHeight = size.height
            nodeWidth = size.height * videoAspectRatio
        } else {
            // Video is taller than scene - fit to width (crop top/bottom)
            nodeWidth = size.width
            nodeHeight = size.width / videoAspectRatio
        }
        
        node.size = CGSize(width: nodeWidth, height: nodeHeight)
    }
    
    // MARK: - Public Methods
    
    /// Load video from URL and extract frames
    func loadVideo(from url: URL) {
        print("[VideoScene] Loading video from: \(url)")
        self.videoURL = url
        
        onLoadingStateChanged?(true, "正在处理视频...")
        
        // Extract frames in background
        Task {
            await extractFrames(from: url)
        }
    }
    
    /// Start playing the video loop
    func startAnimation() {
        guard isLoaded, !textures.isEmpty, !isAnimating, let node = videoNode else { return }
        
        isAnimating = true
        node.removeAction(forKey: "videoLoop")
        
        // Use resize: false to avoid resampling textures during animation (smoother)
        let animate = SKAction.animate(with: textures, timePerFrame: timePerFrame, resize: false, restore: false)
        let forever = SKAction.repeatForever(animate)
        
        node.run(forever, withKey: "videoLoop")
        print("[VideoScene] Animation started with \(textures.count) frames at \(1.0/timePerFrame) fps")
    }
    
    /// Stop the animation
    func stopAnimation() {
        isAnimating = false
        videoNode?.removeAction(forKey: "videoLoop")
        print("[VideoScene] Animation stopped")
    }
    
    /// Clear all loaded frames to free memory
    func clearFrames() {
        stopAnimation()
        textures.removeAll()
        isLoaded = false
        print("[VideoScene] Frames cleared")
    }
    
    // MARK: - Frame Extraction
    
    private func extractFrames(from url: URL) async {
        let asset = AVURLAsset(url: url)
        
        // Get video duration
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            print("[VideoScene] Failed to load duration: \(error)")
            await MainActor.run {
                onLoadingStateChanged?(false, "无法读取视频")
            }
            return
        }
        
        let durationSeconds = CMTimeGetSeconds(duration)
        print("[VideoScene] Video duration: \(durationSeconds)s")
        
        // Calculate frame interval
        let frameInterval = 1.0 / targetFPS
        let totalFrames = min(Int(durationSeconds * targetFPS), maxFrames)
        
        self.timePerFrame = frameInterval
        
        print("[VideoScene] Will extract \(totalFrames) frames at \(targetFPS) fps")
        
        // Get video track to determine aspect ratio
        var videoSize = CGSize(width: 320, height: 180) // Default
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                // Apply transform to get correct orientation
                let transformedSize = naturalSize.applying(transform)
                videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                print("[VideoScene] Video natural size: \(videoSize)")
            }
        } catch {
            print("[VideoScene] Failed to get video size: \(error)")
        }
        
        // Calculate aspect ratio
        let aspectRatio = videoSize.width / videoSize.height
        await MainActor.run {
            self.videoAspectRatio = aspectRatio
        }
        
        // Create image generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        // Calculate target size maintaining aspect ratio
        // Use higher resolution for better quality
        let maxDimension: CGFloat = 640
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        if aspectRatio > 1 {
            // Landscape
            targetWidth = maxDimension
            targetHeight = maxDimension / aspectRatio
        } else {
            // Portrait or square
            targetHeight = maxDimension
            targetWidth = maxDimension * aspectRatio
        }
        generator.maximumSize = CGSize(width: targetWidth, height: targetHeight)
        print("[VideoScene] Frame extraction size: \(targetWidth) x \(targetHeight)")
        
        var extractedTextures: [SKTexture] = []
        
        for i in 0..<totalFrames {
            let time = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: 600)
            
            do {
                let (image, _) = try await generator.image(at: time)
                let uiImage = UIImage(cgImage: image)
                let texture = SKTexture(image: uiImage)
                // Use nearest filtering for better performance, linear for quality
                texture.filteringMode = .linear
                // Preload texture to GPU for smoother playback
                texture.preload {
                    // Texture loaded to GPU
                }
                extractedTextures.append(texture)
                
                // Report progress periodically
                if i % 30 == 0 {
                    let progress = Int(Double(i) / Double(totalFrames) * 100)
                    print("[VideoScene] Extracted \(i)/\(totalFrames) frames (\(progress)%)")
                    await MainActor.run {
                        self.onLoadingStateChanged?(true, "处理中 \(progress)%")
                    }
                }
            } catch {
                print("[VideoScene] Failed to extract frame at \(CMTimeGetSeconds(time))s: \(error)")
                // Continue with next frame
            }
        }
        
        print("[VideoScene] Extraction complete: \(extractedTextures.count) frames")
        
        // Update on main thread
        await MainActor.run {
            self.textures = extractedTextures
            self.isLoaded = !extractedTextures.isEmpty
            
            if self.isLoaded {
                // Update node with first texture
                if let firstTexture = extractedTextures.first {
                    self.videoNode?.texture = firstTexture
                }
                // Apply aspect-fit layout
                self.updateVideoNodeLayout()
                self.onLoadingStateChanged?(false, nil)
            } else {
                self.onLoadingStateChanged?(false, "无法提取视频帧")
            }
        }
    }
}
