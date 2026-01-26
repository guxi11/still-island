//
//  PiPSectionView.swift
//  Still Island
//
//  Section view with dual-column grid layout for PiP providers.
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
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        Section {
            // Dual-column grid of providers
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(registry.availableProviders) { providerType in
                    PiPItemView(
                        providerType: providerType,
                        isActive: isProviderActive(providerType),
                        isPreparing: isProviderPreparing(providerType),
                        onTap: {
                            handleProviderTap(providerType)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
            
            // PiP preview host - required for PiP to work
            if pipManager.isPreparingPiP || pipManager.isPiPActive {
                PiPHostView(
                    displayLayer: pipManager.displayLayer ?? AVSampleBufferDisplayLayer(),
                    onViewCreated: { view in
                        print("[PiPSectionView] SampleBufferDisplayView created")
                        pipManager.bindToViewLayer(view)
                    }
                )
                .id(pipViewId)
                .frame(height: 1) // Minimal height, just needs to be in view hierarchy
                .opacity(0.01) // Almost invisible
            }
            
            // Error message
            if let error = pipManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("悬浮窗口")
        } footer: {
            Text("点击启动悬浮窗口，切换到其他应用后可见")
                .font(.caption2)
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
    List {
        PiPSectionView(pipManager: PiPManager.shared)
    }
}
