//
//  DisplaySession.swift
//  Still Island
//
//  SwiftData model for tracking PiP display sessions.
//

import Foundation
import SwiftData

/// Represents a single PiP display session with duration tracking.
@Model
final class DisplaySession {
    /// Unique identifier for this session
    var id: UUID = UUID()
    
    /// Type of content provider (e.g., "time", "timer")
    var providerType: String = ""
    
    /// When the PiP session started
    var startTime: Date = Date()
    
    /// When the PiP session ended (nil if still active)
    var endTime: Date?
    
    /// Duration in seconds (calculated and stored when session ends)
    var duration: TimeInterval = 0
    
    /// JSON encoded away intervals data (for SwiftData persistence)
    var awayIntervalsData: Data?
    
    /// Away intervals when user's screen was off during this session
    var awayIntervals: [AwayInterval] {
        get {
            guard let data = awayIntervalsData else { return [] }
            return (try? JSONDecoder().decode([AwayInterval].self, from: data)) ?? []
        }
        set {
            awayIntervalsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Total duration of all away intervals in seconds
    var totalAwayDuration: TimeInterval {
        awayIntervals.reduce(0) { $0 + $1.duration }
    }
    
    /// Active usage duration (total duration minus away time)
    var activeUsageDuration: TimeInterval {
        max(0, duration - totalAwayDuration)
    }
    
    /// Formatted away duration string
    var formattedAwayDuration: String {
        let totalSeconds = Int(totalAwayDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Formatted duration string (HH:MM:SS or MM:SS)
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    init(providerType: String) {
        self.id = UUID()
        self.providerType = providerType
        self.startTime = Date()
        self.endTime = nil
        self.duration = 0
        self.awayIntervalsData = nil
    }
    
    /// Marks the session as ended and calculates final duration
    func endSession() {
        if endTime == nil {
            let now = Date()
            endTime = now
            duration = now.timeIntervalSince(startTime)
        }
    }
    
    /// Adds a completed away interval to this session
    func addAwayInterval(_ interval: AwayInterval) {
        var intervals = awayIntervals
        intervals.append(interval)
        awayIntervals = intervals
    }
}

// MARK: - Query Helpers

extension DisplaySession {
    /// Predicate for sessions on a specific date
    static func predicate(for date: Date) -> Predicate<DisplaySession> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return #Predicate<DisplaySession> { session in
            session.startTime >= startOfDay && session.startTime < endOfDay
        }
    }
    
    /// Predicate for sessions in a date range
    static func predicate(from startDate: Date, to endDate: Date) -> Predicate<DisplaySession> {
        return #Predicate<DisplaySession> { session in
            session.startTime >= startDate && session.startTime < endDate
        }
    }
}
