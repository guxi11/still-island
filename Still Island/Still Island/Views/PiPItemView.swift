//
//  PiPItemView.swift
//  Still Island
//
//  Single PiP content item view with iOS Shortcuts style layout.
//

import SwiftUI

/// View for displaying a single PiP provider option in the grid - iOS Shortcuts style
struct PiPItemView: View {
    let providerType: PiPProviderType
    let isActive: Bool
    let isPreparing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Preview fills entire card
                PiPStaticPreview(providerType: providerType)
                
                // Label overlay at bottom-left
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: providerType.iconName)
                                .font(.caption2)
                            Text(providerType.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.5))
                        )
                        Spacer()
                    }
                    .padding(8)
                }
                
                // Status indicator at top-right
                if isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        )
                        .padding(8)
                } else if isPreparing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(8)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.green : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
    }
}

#Preview {
    HStack(spacing: 12) {
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
    .padding()
}
