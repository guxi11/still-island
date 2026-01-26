//
//  PiPItemView.swift
//  Still Island
//
//  Single PiP content item view with preview and status indicator.
//

import SwiftUI

/// View for displaying a single PiP provider option in the grid
struct PiPItemView: View {
    let providerType: PiPProviderType
    let isActive: Bool
    let isPreparing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Preview area
                ZStack(alignment: .topTrailing) {
                    PiPStaticPreview(providerType: providerType)
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Status indicator
                    if isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .padding(6)
                    } else if isPreparing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .padding(4)
                    }
                }
                
                // Label
                HStack(spacing: 4) {
                    Image(systemName: providerType.iconName)
                        .font(.caption2)
                    Text(providerType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(isActive ? .green : .primary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
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
