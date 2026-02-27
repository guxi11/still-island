//
//  CardInstance.swift
//  Porthole
//
//  SwiftData model representing a card instance on the home page.
//  Supports multiple instances of the same provider type (e.g., multiple video cards).
//

import Foundation
import SwiftData

/// Represents a card instance displayed on the home page
@Model
final class CardInstance {
    var id: UUID = UUID()
    var providerTypeRaw: String = ""
    var displayOrder: Int = 0
    var configurationData: Data?
    var createdAt: Date = Date()

    /// Type-safe access to provider type
    var providerType: PiPProviderType? {
        PiPProviderType(rawValue: providerTypeRaw)
    }

    init(providerType: PiPProviderType, displayOrder: Int, configuration: VideoCardConfiguration? = nil) {
        self.id = UUID()
        self.providerTypeRaw = providerType.rawValue
        self.displayOrder = displayOrder
        self.configurationData = configuration?.encoded()
        self.createdAt = Date()
    }
}

// MARK: - Video Card Configuration

/// Configuration for video cards, storing video URL as bookmark data
struct VideoCardConfiguration: Codable {
    var videoBookmarkData: Data?

    /// Resolve bookmark data back to URL
    var videoURL: URL? {
        get {
            guard let data = videoBookmarkData else { return nil }
            var isStale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    /// Set video URL and create bookmark data
    mutating func setVideoURL(_ url: URL) {
        videoBookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Encode configuration to Data
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decode configuration from Data
    static func decode(from data: Data?) -> VideoCardConfiguration? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode(VideoCardConfiguration.self, from: data)
    }
}
