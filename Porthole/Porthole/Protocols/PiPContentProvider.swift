//
//  PiPContentProvider.swift
//  Porthole
//
//  Protocol for providing content to PiP video stream.
//

import UIKit
import AVFoundation
import CoreMedia

/// Protocol that defines requirements for content providers that can be displayed in PiP window.
/// Implement this protocol to create new content types (e.g., clock, pomodoro timer, weather).
@MainActor
protocol PiPContentProvider: AnyObject {
    /// Unique identifier for this provider type (e.g., "time", "timer")
    /// Used for tracking and statistics.
    static var providerType: String { get }
    
    /// Display name shown in the UI
    static var displayName: String { get }
    
    /// SF Symbol name for the provider icon
    static var iconName: String { get }
    
    /// The view that contains the content to be displayed in PiP.
    /// This view will be captured and converted to video frames.
    var contentView: UIView { get }
    
    /// The preferred frame rate for this content type.
    /// Lower frame rates save battery. Recommended: 1-10 FPS for mostly static content.
    var preferredFrameRate: Int { get }
    
    /// Called when the PiP starts displaying this content.
    /// Use this to start any timers or updates needed for the content.
    func start()
    
    /// Called when the PiP stops or switches to different content.
    /// Use this to clean up resources, stop timers, etc.
    func stop()
}

// MARK: - Direct Video Output Support

/// Protocol for providers that output video frames directly (e.g., camera).
/// Providers implementing this protocol bypass UIView capture and push frames directly to PiP.
/// This enables background video capture (e.g., camera continues when app is in background).
@MainActor
protocol DirectVideoProvider: PiPContentProvider {
    /// Whether this provider outputs video frames directly.
    /// When true, PiPManager will use direct frame pushing instead of UIView capture.
    var providesDirectVideoOutput: Bool { get }
    
    /// Set the display layer to receive video frames.
    /// Called by PiPManager before start() to provide the output destination.
    func setOutputLayer(_ layer: AVSampleBufferDisplayLayer)
}

// MARK: - Default Implementation

extension DirectVideoProvider {
    /// Default implementation - providers that conform to DirectVideoProvider
    /// typically provide direct output.
    var providesDirectVideoOutput: Bool { true }
}
