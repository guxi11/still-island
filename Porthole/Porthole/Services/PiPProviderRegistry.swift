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
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .time: return TimeDisplayProvider.displayName
        case .timer: return TimerProvider.displayName
        case .camera: return CameraProvider.displayName
        case .cat: return CatCompanionProvider.displayName
        }
    }
    
    var iconName: String {
        switch self {
        case .time: return TimeDisplayProvider.iconName
        case .timer: return TimerProvider.iconName
        case .camera: return CameraProvider.iconName
        case .cat: return CatCompanionProvider.iconName
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
