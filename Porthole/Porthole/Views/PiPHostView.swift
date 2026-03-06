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
        guard let layer = layer as? AVSampleBufferDisplayLayer else {
            print("[SampleBufferDisplayView] CRITICAL ERROR: Layer is not AVSampleBufferDisplayLayer. Actual type: \(type(of: layer))")
            // Return a temporary layer to avoid crash, though PiP won't work correctly
            return AVSampleBufferDisplayLayer()
        }
        return layer
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
        
        // 添加圆角
        layer.cornerRadius = 12
        layer.masksToBounds = true
        
        // Configure the layer
        let sbLayer = sampleBufferDisplayLayer
        sbLayer.backgroundColor = UIColor.black.cgColor
        // 使用 .resize 而不是 .resizeAspect，避免内容根据 layer bounds 变化而产生缩放动画
        // 因为我们的帧尺寸 (400x200) 和 preferredContentSize (400x200) 是一致的
        sbLayer.videoGravity = .resize
        sbLayer.cornerRadius = 12
        
        print("[SampleBufferDisplayView] Created with layerClass override")
        print("[SampleBufferDisplayView] layer: \(sbLayer)")
    }
    
    override func layoutSubviews() {
        // 禁用 bounds 变化时的隐式动画
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layoutSubviews()
        CATransaction.commit()
        print("[SampleBufferDisplayView] layoutSubviews - bounds: \(bounds), layer.bounds: \(layer.bounds)")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        print("[SampleBufferDisplayView] didMoveToSuperview - superview: \(String(describing: superview)), bounds: \(bounds)")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        print("[SampleBufferDisplayView] didMoveToWindow - window: \(String(describing: window)), bounds: \(bounds)")
    }
}
