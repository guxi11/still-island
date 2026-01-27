//
//  PiPSectionView.swift
//  Still Island
//
//  Section view with dual-column grid layout for PiP providers.
//  PiP host view is now embedded inside each card to avoid layout reflow.
//

import SwiftUI
import AVKit

/// Section container for PiP provider selection with dual-column grid layout
struct PiPSectionView: View {
    @ObservedObject var pipManager: PiPManager
    @StateObject private var registry = PiPProviderRegistry.shared
    
    // Keep strong reference to current provider
    @State private var currentProvider: PiPContentProvider?
    @State private var pipViewId = UUID()
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Dual-column grid of providers - minimal artistic style
            // PiP host view is embedded inside each card (no external host)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(registry.availableProviders) { providerType in
                    PiPItemView(
                        providerType: providerType,
                        isActive: isProviderActive(providerType),
                        isPreparing: isProviderPreparing(providerType),
                        onTap: {
                            handleProviderTap(providerType)
                        },
                        onPiPViewCreated: isProviderActive(providerType) || isProviderPreparing(providerType) ? { view in
                            print("[PiPSectionView] SampleBufferDisplayView created inside card")
                            pipManager.bindToViewLayer(view)
                        } : nil,
                        displayLayer: isProviderActive(providerType) || isProviderPreparing(providerType) ? pipManager.displayLayer : nil
                    )
                    .id(isProviderActive(providerType) || isProviderPreparing(providerType) ? pipViewId : UUID())
                }
            }
            
            // Error message - subtle style
            if let error = pipManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func isProviderActive(_ type: PiPProviderType) -> Bool {
        pipManager.isPiPActive && pipManager.currentProviderType == type.rawValue
    }
    
    private func isProviderPreparing(_ type: PiPProviderType) -> Bool {
        pipManager.isPreparingPiP && pipManager.currentProviderType == type.rawValue
    }
    
    private func handleProviderTap(_ type: PiPProviderType) {
        // If this provider is already active, stop it
        if isProviderActive(type) || isProviderPreparing(type) {
            pipManager.stopPiP()
            currentProvider = nil
            return
        }
        
        // If another provider is active, stop it first
        if pipManager.isPiPActive || pipManager.isPreparingPiP {
            pipManager.stopPiP()
            currentProvider = nil
        }
        
        // Generate new view ID to force recreation
        pipViewId = UUID()
        
        // Create and start new provider
        let provider = type.createProvider()
        currentProvider = provider
        pipManager.preparePiP(provider: provider)
    }
}

#Preview {
    PiPSectionView(pipManager: PiPManager.shared)
        .padding()
}
