//
//  AwayInterval.swift
//  Porthole
//
//  Represents a time interval when the user was away (screen off) during a PiP session.
//

import Foundation

/// Represents a single "away" interval when the user's screen was off
/// but PiP was still active.
struct AwayInterval: Codable, Identifiable, Equatable {
    let id: UUID
    let startTime: Date       // When screen turned off
    var endTime: Date?        // When screen turned back on
    
    init(id: UUID = UUID(), startTime: Date = Date(), endTime: Date? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
    }
    
    /// Duration of this away interval in seconds
    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }
    
    /// Formatted duration string (e.g., "5:30" or "1:23:45")
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// User-friendly description of the duration
    var durationDescription: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "\(totalSeconds)秒"
        }
    }
}
