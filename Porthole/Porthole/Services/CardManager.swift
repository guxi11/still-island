//
//  CardManager.swift
//  Porthole
//
//  Manages the user's card configuration on the home page.
//  Handles CRUD operations and persistence via SwiftData.
//

import Foundation
import SwiftData
import SwiftUI

/// Manages the user's card configuration on the home page
@MainActor
final class CardManager: ObservableObject {

    static let shared = CardManager()

    @Published private(set) var cards: [CardInstance] = []

    private var modelContext: ModelContext?
    
    /// The ID of the last opened card, persisted in UserDefaults
    var lastOpenedCardId: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: "lastOpenedCardId") else { return nil }
            return UUID(uuidString: uuidString)
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: "lastOpenedCardId")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastOpenedCardId")
            }
        }
    }

    private init() {}

    // MARK: - Configuration

    func configure(with container: ModelContainer) {
        self.modelContext = container.mainContext
        loadCards()
    }

    // MARK: - Card Operations

    func loadCards() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<CardInstance>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )

        do {
            cards = try context.fetch(descriptor)

            // If no cards exist, create default set
            if cards.isEmpty {
                createDefaultCards()
            }
        } catch {
            print("[CardManager] Failed to fetch cards: \(error)")
        }
    }

    private func createDefaultCards() {
        guard let context = modelContext else { return }

        // Migrate existing video URL from old storage
        let migratedVideoConfig = migrateExistingVideoURL()

        // Create default cards for all provider types
        for (index, providerType) in PiPProviderType.allCases.enumerated() {
            let config = (providerType == .video) ? migratedVideoConfig : nil
            let card = CardInstance(providerType: providerType, displayOrder: index, configuration: config)
            context.insert(card)
        }

        save()
        loadCards()
    }

    /// Migrate existing video URL from UserDefaults to new model
    private func migrateExistingVideoURL() -> VideoCardConfiguration? {
        let videoURLKey = "VideoLoopProvider.savedVideoURL"
        guard let bookmarkData = UserDefaults.standard.data(forKey: videoURLKey) else {
            return nil
        }

        // Create configuration with existing bookmark data
        var config = VideoCardConfiguration()
        config.videoBookmarkData = bookmarkData

        // Remove old UserDefaults key
        UserDefaults.standard.removeObject(forKey: videoURLKey)
        print("[CardManager] Migrated existing video URL from UserDefaults")

        return config
    }

    /// Adds a new card instance at the end
    func addCard(providerType: PiPProviderType, configuration: VideoCardConfiguration? = nil) {
        addCard(providerType: providerType, afterIndex: cards.count - 1, configuration: configuration)
    }
    
    /// Adds a new card instance after a specific index
    /// - Parameters:
    ///   - providerType: The type of provider for the new card
    ///   - afterIndex: Insert after this index (-1 to insert at beginning)
    ///   - configuration: Optional configuration data
    /// - Returns: The index of the newly inserted card, or nil if failed
    @discardableResult
    func addCard(providerType: PiPProviderType, afterIndex: Int, configuration: VideoCardConfiguration? = nil) -> Int? {
        guard let context = modelContext else { return nil }

        // Check if unique card already exists
        if !providerType.allowsMultipleInstances {
            if cards.contains(where: { $0.providerTypeRaw == providerType.rawValue }) {
                print("[CardManager] Card of type \(providerType.rawValue) already exists")
                return nil
            }
        }

        let insertIndex = afterIndex + 1
        
        // Shift all cards after insertIndex
        for card in cards where card.displayOrder >= insertIndex {
            card.displayOrder += 1
        }
        
        let card = CardInstance(providerType: providerType, displayOrder: insertIndex, configuration: configuration)
        context.insert(card)

        save()
        loadCards()
        print("[CardManager] Added card: \(providerType.rawValue) at index \(insertIndex)")
        return insertIndex
    }

    /// Removes a card by ID
    func removeCard(id: UUID) {
        guard let context = modelContext else { return }
        guard let card = cards.first(where: { $0.id == id }) else { return }

        let providerType = card.providerTypeRaw
        context.delete(card)

        save()
        loadCards()
        print("[CardManager] Removed card: \(providerType)")
    }

    /// Updates video configuration for a card
    func updateVideoConfiguration(cardId: UUID, videoURL: URL) {
        guard let card = cards.first(where: { $0.id == cardId }) else { return }

        var config = VideoCardConfiguration.decode(from: card.configurationData) ?? VideoCardConfiguration()
        config.setVideoURL(videoURL)
        card.configurationData = config.encoded()

        save()
        loadCards()
        print("[CardManager] Updated video configuration for card: \(cardId)")
    }
    
    /// Updates the last opened card ID
    func updateLastOpenedCard(id: UUID) {
        lastOpenedCardId = id
    }

    /// Gets available provider types that can be added
    func availableProvidersToAdd() -> [PiPProviderType] {
        var available: [PiPProviderType] = []

        for providerType in PiPProviderType.allCases {
            if providerType.allowsMultipleInstances {
                // Repeatable cards are always available
                available.append(providerType)
            } else {
                // Unique cards only if not already present
                if !cards.contains(where: { $0.providerTypeRaw == providerType.rawValue }) {
                    available.append(providerType)
                }
            }
        }

        return available
    }

    /// Check if any cards can be added
    var canAddCards: Bool {
        !availableProvidersToAdd().isEmpty
    }

    // MARK: - Private Helpers

    private func save() {
        do {
            try modelContext?.save()
        } catch {
            print("[CardManager] Failed to save: \(error)")
        }
    }
}
