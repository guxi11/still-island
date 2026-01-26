//
//  PiPContentProvider.swift
//  Still Island
//
//  Protocol for providing content to PiP video stream.
//

import UIKit

/// Protocol that defines requirements for content providers that can be displayed in PiP window.
/// Implement this protocol to create new content types (e.g., clock, pomodoro timer, weather).
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
