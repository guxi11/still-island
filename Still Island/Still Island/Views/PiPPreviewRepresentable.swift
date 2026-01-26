//
//  PiPPreviewRepresentable.swift
//  Still Island
//
//  SwiftUI wrapper for displaying PiP content preview.
//

import SwiftUI
import UIKit

/// SwiftUI representable for displaying a live preview of PiP content
struct PiPPreviewRepresentable: UIViewRepresentable {
    let providerType: PiPProviderType
    @Binding var provider: PiPContentProvider?
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true
        
        // Create the provider and add its content view
        let newProvider = providerType.createProvider()
        
        let contentView = newProvider.contentView
        contentView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        containerView.addSubview(contentView)
        
        // Start the provider for live preview
        newProvider.start()
        
        // Store reference
        DispatchQueue.main.async {
            self.provider = newProvider
        }
        
        context.coordinator.provider = newProvider
        context.coordinator.contentView = contentView
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Center the scaled content view
        if let contentView = context.coordinator.contentView {
            let scaledWidth = contentView.bounds.width * 0.5
            let scaledHeight = contentView.bounds.height * 0.5
            contentView.center = CGPoint(
                x: uiView.bounds.midX,
                y: uiView.bounds.midY
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var provider: PiPContentProvider?
        var contentView: UIView?
        
        deinit {
            provider?.stop()
        }
    }
}

/// A simpler static preview that doesn't run the provider
struct PiPStaticPreview: View {
    let providerType: PiPProviderType
    
    var body: some View {
        ZStack {
            // Background matching provider style
            backgroundColor
            
            // Content preview - larger text for iOS Shortcuts style
            Text(previewText)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .foregroundStyle(foregroundColor)
        }
    }
    
    private var backgroundColor: Color {
        switch providerType {
        case .time:
            return Color(red: 0.1, green: 0.1, blue: 0.15)
        case .timer:
            return Color(red: 0.1, green: 0.15, blue: 0.1)
        }
    }
    
    private var foregroundColor: Color {
        switch providerType {
        case .time:
            return .white
        case .timer:
            return Color(red: 0.4, green: 1.0, blue: 0.4)
        }
    }
    
    private var previewText: String {
        switch providerType {
        case .time:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: Date())
        case .timer:
            return "00:00"
        }
    }
}
