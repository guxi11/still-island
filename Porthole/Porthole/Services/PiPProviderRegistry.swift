//
//  PiPProviderRegistry.swift
//  Porthole
//
//  Registry for available PiP content providers.
//

import Foundation

/// Enum representing available PiP provider types
@MainActor
enum PiPProviderType: String, CaseIterable, Identifiable {
    case time = "time"
    case timer = "timer"
    case camera = "camera"
    case sharedCamera = "sharedCamera"  // 实景共享 - 支持 VoIP 后台模式
    case cat = "cat"
    case video = "video"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .time: return TimeDisplayProvider.displayName
        case .timer: return TimerProvider.displayName
        case .camera: return CameraProvider.displayName
        case .sharedCamera: return SharedCameraProvider.displayName
        case .cat: return CatCompanionProvider.displayName
        case .video: return VideoLoopProvider.displayName
        }
    }

    var iconName: String {
        switch self {
        case .time: return TimeDisplayProvider.iconName
        case .timer: return TimerProvider.iconName
        case .camera: return CameraProvider.iconName
        case .sharedCamera: return SharedCameraProvider.iconName
        case .cat: return CatCompanionProvider.iconName
        case .video: return VideoLoopProvider.iconName
        }
    }

    /// Whether the provider has a light background (for text color adjustment)
    var hasLightBackground: Bool {
        // 所有卡片都是深色背景
        return false
    }

    /// Whether this provider type supports custom content (like video selection)
    var supportsCustomContent: Bool {
        switch self {
        case .video: return true
        default: return false
        }
    }
    
    /// Whether this provider type requires room setup before use
    var requiresRoomSetup: Bool {
        switch self {
        case .sharedCamera: return true
        default: return false
        }
    }

    /// Whether multiple instances of this provider type are allowed on the home page
    var allowsMultipleInstances: Bool {
        switch self {
        case .video: return true
        case .time, .timer, .camera, .sharedCamera, .cat: return false
        }
    }

    /// Creates a new instance of the provider
    func createProvider() -> PiPContentProvider {
        switch self {
        case .time:
            return TimeDisplayProvider()
        case .timer:
            return TimerProvider()
        case .camera:
            return CameraProvider()
        case .sharedCamera:
            return SharedCameraProvider()
        case .cat:
            return CatCompanionProvider()
        case .video:
            return VideoLoopProvider()
        }
    }

    /// Creates a new instance of the provider with optional configuration
    func createProvider(with configuration: Data?) -> PiPContentProvider {
        switch self {
        case .time:
            return TimeDisplayProvider()
        case .timer:
            return TimerProvider()
        case .camera:
            return CameraProvider()
        case .sharedCamera:
            return SharedCameraProvider()
        case .cat:
            return CatCompanionProvider()
        case .video:
            let provider = VideoLoopProvider()
            // Load video URL from configuration if provided
            if let config = VideoCardConfiguration.decode(from: configuration),
               let url = config.videoURL {
                provider.setVideoURL(url)
            }
            return provider
        }
    }
}

/// Registry that manages available PiP content providers
@MainActor
final class PiPProviderRegistry: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PiPProviderRegistry()
    
    // MARK: - Published Properties
    
    /// All available provider types
    @Published private(set) var availableProviders: [PiPProviderType] = PiPProviderType.allCases
    
    // MARK: - Initialization
    
    private init() {
        print("[PiPProviderRegistry] Initialized with \(availableProviders.count) providers")
    }
}
