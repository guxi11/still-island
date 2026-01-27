//
//  PiPItemView.swift
//  Porthole
//
//  Single PiP content item view with silhouette state for seamless transitions.
//  PiP host view is embedded inside the card to avoid layout reflow.
//

import SwiftUI
import AVKit

/// View for displaying a single PiP provider option in the grid
/// Supports silhouette state when PiP is active to avoid layout reflow
struct PiPItemView: View {
    let providerType: PiPProviderType
    let isActive: Bool
    let isPreparing: Bool
    let onTap: () -> Void
    
    /// Callback to bind PiP view layer when created
    var onPiPViewCreated: ((SampleBufferDisplayView) -> Void)?
    
    /// Display layer for PiP (only needed when preparing/active)
    var displayLayer: AVSampleBufferDisplayLayer?
    
    // Animation state
    @State private var isPressed = false
    
    /// Returns true when the card should show silhouette (PiP is running)
    private var showSilhouette: Bool {
        isActive
    }
    
    /// Returns true when we need the PiP host view inside this card
    private var needsPiPHost: Bool {
        isPreparing || isActive
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if showSilhouette {
                    // Silhouette state - artistic placeholder
                    silhouetteView
                } else {
                    // Normal preview state
                    normalView
                }
                
                // Hidden PiP host view - embedded in card to avoid layout reflow
                if needsPiPHost, let layer = displayLayer {
                    PiPHostView(
                        displayLayer: layer,
                        onViewCreated: onPiPViewCreated
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(showSilhouette ? 0.05 : 0.08), radius: showSilhouette ? 4 : 8, x: 0, y: showSilhouette ? 2 : 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .animation(.easeInOut(duration: 0.3), value: showSilhouette)
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
    
    // MARK: - Subviews
    
    /// Normal preview card view
    private var normalView: some View {
        ZStack(alignment: .topTrailing) {
            // Preview fills entire card
            PiPStaticPreview(providerType: providerType)
            
            // Label at bottom-left - simple text
            VStack {
                Spacer()
                HStack {
                    Text(providerType.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    Spacer()
                }
                .padding(12)
            }
            
            // Preparing indicator at top-right
            if isPreparing {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .padding(8)
            }
        }
    }
    
    /// Silhouette view when PiP is active - tap to close
    private var silhouetteView: some View {
        ZStack {
            // Frosted glass background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
            
            // Subtle inner content
            VStack(spacing: 12) {
                // Icon in a circle
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: providerType.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                // "Tap to close" hint
                Text("轻触关闭")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            
            // Active indicator - pulsing dot
            VStack {
                HStack {
                    Spacer()
                    PulsingDot()
                        .padding(12)
                }
                Spacer()
            }
        }
    }
}

/// Pulsing dot indicator for active state
struct PulsingDot: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color.green.opacity(0.4), lineWidth: 2)
                    .scaleEffect(isPulsing ? 2 : 1)
                    .opacity(isPulsing ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            PiPItemView(
                providerType: .time,
                isActive: false,
                isPreparing: false,
                onTap: {}
            )
            
            PiPItemView(
                providerType: .timer,
                isActive: true,
                isPreparing: false,
                onTap: {}
            )
        }
        
        HStack(spacing: 16) {
            PiPItemView(
                providerType: .time,
                isActive: false,
                isPreparing: true,
                onTap: {}
            )
            
            PiPItemView(
                providerType: .timer,
                isActive: false,
                isPreparing: false,
                onTap: {}
            )
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
