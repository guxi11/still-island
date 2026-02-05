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
    case cat = "cat"
    case video = "video"
    case focusRoom = "focusRoom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .time: return TimeDisplayProvider.displayName
        case .timer: return TimerProvider.displayName
        case .camera: return CameraProvider.displayName
        case .cat: return CatCompanionProvider.displayName
        case .video: return VideoLoopProvider.displayName
        case .focusRoom: return FocusRoomProvider.displayName
        }
    }

    var iconName: String {
        switch self {
        case .time: return TimeDisplayProvider.iconName
        case .timer: return TimerProvider.iconName
        case .camera: return CameraProvider.iconName
        case .cat: return CatCompanionProvider.iconName
        case .video: return VideoLoopProvider.iconName
        case .focusRoom: return FocusRoomProvider.iconName
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

    /// Whether multiple instances of this provider type are allowed on the home page
    var allowsMultipleInstances: Bool {
        switch self {
        case .video: return true
        case .time, .timer, .camera, .cat, .focusRoom: return false
        }
    }
    
    /// Whether this provider requires joining a focus room first
    var requiresFocusRoom: Bool {
        switch self {
        case .focusRoom: return true
        default: return false
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
        case .cat:
            return CatCompanionProvider()
        case .video:
            return VideoLoopProvider()
        case .focusRoom:
            return FocusRoomProvider()
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
        case .focusRoom:
            return FocusRoomProvider()
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
