//
//  PiPHostView.swift
//  Porthole
//
//  A UIViewRepresentable that hosts the AVSampleBufferDisplayLayer for PiP.
//

import SwiftUI
import AVKit

/// A SwiftUI view that hosts the PiP display layer.
/// The layer must be in the view hierarchy with valid frame for PiP to work.
struct PiPHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    let onViewCreated: ((SampleBufferDisplayView) -> Void)?
    
    init(displayLayer: AVSampleBufferDisplayLayer, onViewCreated: ((SampleBufferDisplayView) -> Void)? = nil) {
        self.displayLayer = displayLayer
        self.onViewCreated = onViewCreated
    }
    
    func makeUIView(context: Context) -> SampleBufferDisplayView {
        let view = SampleBufferDisplayView()
        // Copy configuration from external layer to view's layer
        view.sampleBufferDisplayLayer.controlTimebase = displayLayer.controlTimebase
        onViewCreated?(view)
        return view
    }
    
    func updateUIView(_ uiView: SampleBufferDisplayView, context: Context) {
        // Nothing to update
    }
}

/// Custom UIView that uses AVSampleBufferDisplayLayer as its backing layer via layerClass override.
/// This is the required approach for PiP with AVSampleBufferDisplayLayer.
class SampleBufferDisplayView: UIView {
    
    // CRITICAL: Override layerClass to use AVSampleBufferDisplayLayer as root layer
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
    
    /// The AVSampleBufferDisplayLayer that backs this view
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        backgroundColor = .black
        clipsToBounds = true
        
        // Configure the layer
        let sbLayer = sampleBufferDisplayLayer
        sbLayer.backgroundColor = UIColor.black.cgColor
        sbLayer.videoGravity = .resizeAspect
        
        print("[SampleBufferDisplayView] Created with layerClass override")
        print("[SampleBufferDisplayView] layer: \(sbLayer)")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && bounds.height > 0 {
            print("[SampleBufferDisplayView] Layout with bounds: \(bounds)")
        }
    }
}
