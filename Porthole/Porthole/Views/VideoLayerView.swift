//
//  VideoLayerView.swift
//  Porthole
//
//  Container view that automatically updates display layer frame
//

import UIKit
import AVFoundation

/// Container view for AVSampleBufferDisplayLayer that auto-updates on layout changes
class VideoLayerView: UIView {
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update all AVSampleBufferDisplayLayer sublayers
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                if sublayer is AVSampleBufferDisplayLayer {
                    sublayer.frame = bounds
                }
            }
        }
    }
}
