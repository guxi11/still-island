//
//  PiPPreviewRepresentable.swift
//  Porthole
//
//  SwiftUI wrapper for displaying PiP content preview.
//

import SwiftUI
import UIKit
import AVFoundation

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
            // Stop provider on main actor
            if let provider = provider {
                Task { @MainActor in
                    provider.stop()
                }
            }
        }
    }
}

/// A simpler static preview that doesn't run the provider
struct PiPStaticPreview: View {
    let providerType: PiPProviderType
    /// Optional video URL for video cards to display thumbnail
    var videoURL: URL?

    var body: some View {
        ZStack {
            // Background matching provider style
            backgroundColor

            // Content preview
            switch providerType {
            case .camera:
                // Camera shows icon instead of text
                VStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            case .cat:
                // Show cat emoji on white background
                Text("🐱")
                    .font(.system(size: 50))
            case .video:
                // Video shows thumbnail if available, otherwise play icon
                if let url = videoURL {
                    VideoThumbnailView(videoURL: url)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            default:
                Text(previewText)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundStyle(foregroundColor)
            }
        }
    }

    private var backgroundColor: Color {
        switch providerType {
        case .time:
            return Color(red: 0.1, green: 0.1, blue: 0.15)
        case .timer:
            return Color(red: 0.1, green: 0.15, blue: 0.1)
        case .camera:
            return Color(red: 0.15, green: 0.12, blue: 0.18)
        case .cat:
            return .white
        case .video:
            return Color(red: 0.12, green: 0.1, blue: 0.18)
        }
    }

    private var foregroundColor: Color {
        switch providerType {
        case .time:
            return .white
        case .timer:
            return Color(red: 0.4, green: 1.0, blue: 0.4)
        case .camera:
            return .white
        case .cat:
            return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .video:
            return .white
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
        case .camera:
            return ""
        case .cat:
            return ""
        case .video:
            return ""
        }
    }
}

/// View for displaying video thumbnail
struct VideoThumbnailView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                // Fallback while loading
                Color(red: 0.12, green: 0.1, blue: 0.18)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.7)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: videoURL) { _, _ in
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)

            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                await MainActor.run {
                    thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("[VideoThumbnailView] Failed to generate thumbnail: \(error)")
            }
        }
    }
}

/// A cute cat face preview for the cat provider card
struct CatPreviewShape: View {
    let catColor = Color(red: 0.95, green: 0.6, blue: 0.3)
    let catDarkColor = Color(red: 0.85, green: 0.5, blue: 0.2)
    let pink = Color(red: 1.0, green: 0.7, blue: 0.75)
    
    var body: some View {
        ZStack {
            // Head
            Ellipse()
                .fill(catColor)
                .frame(width: 50, height: 45)
            
            // Left ear
            Triangle()
                .fill(catColor)
                .frame(width: 16, height: 16)
                .offset(x: -15, y: -22)
            
            // Right ear
            Triangle()
                .fill(catColor)
                .frame(width: 16, height: 16)
                .offset(x: 15, y: -22)
            
            // Left eye
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .offset(x: -10, y: -2)
            
            // Right eye
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .offset(x: 10, y: -2)
            
            // Left pupil
            Circle()
                .fill(.black)
                .frame(width: 6, height: 6)
                .offset(x: -8, y: -1)
            
            // Right pupil
            Circle()
                .fill(.black)
                .frame(width: 6, height: 6)
                .offset(x: 12, y: -1)
            
            // Nose
            Ellipse()
                .fill(pink)
                .frame(width: 8, height: 6)
                .offset(y: 8)
            
            // Mouth
            Capsule()
                .fill(catDarkColor)
                .frame(width: 6, height: 2)
                .offset(y: 14)
        }
    }
}

/// Simple triangle shape for cat ears
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
