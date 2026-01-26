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
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        // Header outside Section
        Section(header: Text("悬浮窗口")) {
            EmptyView()
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        
        // Dual-column grid of providers - iOS Shortcuts style, no container
        LazyVGrid(columns: columns, spacing: 16) {
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
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        
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
            .frame(height: 1)
            .opacity(0.01)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        
        // Error message
        if let error = pipManager.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .listRowBackground(Color.clear)
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
