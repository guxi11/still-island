//
//  PiPSectionView.swift
//  Porthole
//
//  Section view with dual-column grid layout for PiP providers.
//  Supports user-customizable card list with add/remove functionality.
//

import SwiftUI
import AVKit

/// Section container for PiP provider selection with dual-column grid layout
struct PiPSectionView: View {
    @ObservedObject var pipManager: PiPManager
    @ObservedObject private var cardManager = CardManager.shared

    // Keep strong reference to current provider
    @State private var currentProvider: PiPContentProvider?
    @State private var pipViewId = UUID()

    // Video picker state
    @State private var showVideoPicker = false
    @State private var editingCardId: UUID?

    // Add card sheet state
    @State private var showAddCardSheet = false

    // Track which card instance is currently active
    @State private var activeCardId: UUID?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// Whether any PiP is currently active or preparing
    private var isPiPRunning: Bool {
        pipManager.isPiPActive || pipManager.isPreparingPiP
    }

    var body: some View {
        VStack(spacing: 20) {
            // Top empty area with guide text
            ZStack {
                // Guide text - only show when PiP is not running
                if !isPiPRunning {
                    Text("点击卡片展示舷窗")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .frame(height: 120)

            // Dual-column grid of cards
            LazyVGrid(columns: columns, spacing: 16) {
                // User's cards
                ForEach(cardManager.cards, id: \.id) { card in
                    if let providerType = card.providerType {
                        let videoConfig = VideoCardConfiguration.decode(from: card.configurationData)
                        PiPItemView(
                            providerType: providerType,
                            isActive: isCardActive(card),
                            isPreparing: isCardPreparing(card),
                            onTap: {
                                handleCardTap(card)
                            },
                            onLongPress: nil,
                            onPiPViewCreated: isCardActive(card) || isCardPreparing(card) ? { view in
                                print("[PiPSectionView] SampleBufferDisplayView created inside card")
                                pipManager.bindToViewLayer(view)
                            } : nil,
                            displayLayer: isCardActive(card) || isCardPreparing(card) ? pipManager.displayLayer : nil,
                            videoURL: videoConfig?.videoURL
                        )
                        .contextMenu {
                            cardContextMenu(for: card, providerType: providerType)
                        }
                        .id(isCardActive(card) || isCardPreparing(card) ? pipViewId : card.id)
                    }
                }

                // Add card button
                if cardManager.canAddCards {
                    AddCardButton {
                        showAddCardSheet = true
                    }
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
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerView(isPresented: $showVideoPicker) { url in
                handleVideoPicked(url)
            }
        }
        .sheet(isPresented: $showAddCardSheet) {
            AddCardView { providerType in
                cardManager.addCard(providerType: providerType)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cardContextMenu(for card: CardInstance, providerType: PiPProviderType) -> some View {
        // Change video option (video cards only)
        if providerType == .video {
            Button {
                editingCardId = card.id
                showVideoPicker = true
            } label: {
                Label("更换视频", systemImage: "video.badge.ellipsis")
            }
        }

        // Remove option (for all cards)
        Button(role: .destructive) {
            // Stop PiP if this card is active
            if isCardActive(card) {
                pipManager.stopPiP()
                currentProvider = nil
                activeCardId = nil
            }
            cardManager.removeCard(id: card.id)
        } label: {
            Label("从主页移除", systemImage: "minus.circle")
        }
    }

    // MARK: - Private Methods

    private func isCardActive(_ card: CardInstance) -> Bool {
        pipManager.isPiPActive && activeCardId == card.id
    }

    private func isCardPreparing(_ card: CardInstance) -> Bool {
        pipManager.isPreparingPiP && activeCardId == card.id
    }

    private func handleCardTap(_ card: CardInstance) {
        guard let providerType = card.providerType else { return }

        // If this card is already active, stop it
        if isCardActive(card) || isCardPreparing(card) {
            pipManager.stopPiP()
            currentProvider = nil
            activeCardId = nil
            return
        }

        // If another card is active, stop it first
        if pipManager.isPiPActive || pipManager.isPreparingPiP {
            pipManager.stopPiP()
            currentProvider = nil
            activeCardId = nil
        }

        // For video provider, check if video is selected
        if providerType == .video {
            let config = VideoCardConfiguration.decode(from: card.configurationData)
            if config?.videoURL == nil {
                // No video selected, show picker first
                editingCardId = card.id
                showVideoPicker = true
                return
            }
        }

        // Generate new view ID to force recreation
        pipViewId = UUID()
        activeCardId = card.id

        // Create and start new provider with card's configuration
        let provider = providerType.createProvider(with: card.configurationData)
        currentProvider = provider
        pipManager.preparePiP(provider: provider)
    }

    private func handleVideoPicked(_ url: URL) {
        guard let cardId = editingCardId else { return }

        // Update the card's video configuration
        cardManager.updateVideoConfiguration(cardId: cardId, videoURL: url)

        // Find the card and start PiP if it was a tap-to-start scenario
        if let card = cardManager.cards.first(where: { $0.id == cardId }),
           let providerType = card.providerType {

            editingCardId = nil

            // Generate new view ID to force recreation
            pipViewId = UUID()
            activeCardId = card.id

            // Create provider with updated configuration
            // Need to reload to get updated configurationData
            if let updatedCard = cardManager.cards.first(where: { $0.id == cardId }) {
                let provider = providerType.createProvider(with: updatedCard.configurationData)
                currentProvider = provider
                pipManager.preparePiP(provider: provider)
            }
        }
    }
}

#Preview {
    PiPSectionView(pipManager: PiPManager.shared)
        .padding()
}
