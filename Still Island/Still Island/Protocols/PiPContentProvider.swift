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
