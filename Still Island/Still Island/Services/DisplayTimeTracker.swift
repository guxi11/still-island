//
//  DisplayTimeTracker.swift
//  Still Island
//
//  Service for tracking PiP display session times.
//

import Foundation
import SwiftData

/// Singleton service for tracking PiP display session durations.
/// Automatically records start/end times and persists to SwiftData.
@MainActor
final class DisplayTimeTracker: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = DisplayTimeTracker()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentSession: DisplaySession?
    @Published private(set) var isTracking = false
    
    // MARK: - Private Properties
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    // MARK: - Initialization
    
    private init() {
        print("[DisplayTimeTracker] Initializing...")
    }
    
    /// Configure the tracker with a model container
    func configure(with container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = ModelContext(container)
        print("[DisplayTimeTracker] Configured with model container")
        
        // Check for any unclosed sessions from previous runs
        cleanupUnfinishedSessions()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking a new display session
    /// - Parameter providerType: The type of content provider being displayed
    func startTracking(providerType: String) {
        guard let context = modelContext else {
            print("[DisplayTimeTracker] ERROR: Model context not configured")
            return
        }
        
        // End any existing session first
        if currentSession != nil {
            stopTracking()
        }
        
        // Create new session
        let session = DisplaySession(providerType: providerType)
        context.insert(session)
        
        do {
            try context.save()
            currentSession = session
            isTracking = true
            print("[DisplayTimeTracker] Started tracking session for '\(providerType)'")
        } catch {
            print("[DisplayTimeTracker] ERROR: Failed to save session: \(error)")
        }
    }
    
    /// Stop tracking the current session
    func stopTracking() {
        guard let context = modelContext, let session = currentSession else {
            print("[DisplayTimeTracker] No active session to stop")
            return
        }
        
        session.endSession()
        
        do {
            try context.save()
            print("[DisplayTimeTracker] Stopped tracking session. Duration: \(session.formattedDuration)")
        } catch {
            print("[DisplayTimeTracker] ERROR: Failed to save session end: \(error)")
        }
        
        currentSession = nil
        isTracking = false
    }
    
    /// Get all sessions for a specific date
    func sessions(for date: Date) -> [DisplaySession] {
        guard let context = modelContext else { return [] }
        
        let predicate = DisplaySession.predicate(for: date)
        let descriptor = FetchDescriptor<DisplaySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("[DisplayTimeTracker] ERROR: Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    /// Get all sessions in a date range
    func sessions(from startDate: Date, to endDate: Date) -> [DisplaySession] {
        guard let context = modelContext else { return [] }
        
        let predicate = DisplaySession.predicate(from: startDate, to: endDate)
        let descriptor = FetchDescriptor<DisplaySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("[DisplayTimeTracker] ERROR: Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    /// Get total duration for a specific date
    func totalDuration(for date: Date) -> TimeInterval {
        let sessions = sessions(for: date)
        return sessions.reduce(0) { $0 + $1.duration }
    }
    
    /// Get total duration for a date range
    func totalDuration(from startDate: Date, to endDate: Date) -> TimeInterval {
        let sessions = sessions(from: startDate, to: endDate)
        return sessions.reduce(0) { $0 + $1.duration }
    }
    
    /// Get daily totals for a date range (for charts)
    func dailyTotals(from startDate: Date, to endDate: Date) -> [(date: Date, duration: TimeInterval, byProvider: [String: TimeInterval])] {
        let calendar = Calendar.current
        var results: [(date: Date, duration: TimeInterval, byProvider: [String: TimeInterval])] = []
        
        var currentDate = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        
        while currentDate <= endDay {
            let daySessions = sessions(for: currentDate)
            let totalDuration = daySessions.reduce(0) { $0 + $1.duration }
            
            // Group by provider type
            var byProvider: [String: TimeInterval] = [:]
            for session in daySessions {
                byProvider[session.providerType, default: 0] += session.duration
            }
            
            results.append((date: currentDate, duration: totalDuration, byProvider: byProvider))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    /// Clean up any sessions that weren't properly closed
    private func cleanupUnfinishedSessions() {
        guard let context = modelContext else { return }
        
        // Find sessions without end time
        let descriptor = FetchDescriptor<DisplaySession>(
            predicate: #Predicate<DisplaySession> { $0.endTime == nil }
        )
        
        do {
            let unfinishedSessions = try context.fetch(descriptor)
            
            for session in unfinishedSessions {
                // Use start time + 1 minute as a fallback end time
                // or last known app state time if available
                session.endTime = session.startTime.addingTimeInterval(60)
                print("[DisplayTimeTracker] Cleaned up unfinished session: \(session.id)")
            }
            
            if !unfinishedSessions.isEmpty {
                try context.save()
                print("[DisplayTimeTracker] Cleaned up \(unfinishedSessions.count) unfinished sessions")
            }
        } catch {
            print("[DisplayTimeTracker] ERROR: Failed to cleanup sessions: \(error)")
        }
    }
}
