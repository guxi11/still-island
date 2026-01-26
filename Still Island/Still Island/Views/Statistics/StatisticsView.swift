//
//  StatisticsView.swift
//  Still Island
//
//  Main statistics view with tab switching between calendar and timeline views.
//

import SwiftUI
import SwiftData

/// Main statistics view with summary and view mode selection
struct StatisticsView: View {
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var selectedTab = 0
    @State private var selectedDate = Date()
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            SummaryHeaderView(tracker: tracker)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
            
            // Tab picker
            Picker("视图", selection: $selectedTab) {
                Text("日历").tag(0)
                Text("时间线").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                CalendarStatsView(selectedDate: $selectedDate)
                    .tag(0)
                
                TimelineStatsView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("使用统计")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Summary header showing today's and total usage
struct SummaryHeaderView: View {
    @ObservedObject var tracker: DisplayTimeTracker
    
    var body: some View {
        HStack(spacing: 20) {
            StatCard(
                title: "今日",
                duration: todayDuration,
                icon: "sun.max.fill",
                color: .orange
            )
            
            StatCard(
                title: "本周",
                duration: weekDuration,
                icon: "calendar",
                color: .blue
            )
        }
    }
    
    private var todayDuration: TimeInterval {
        tracker.totalDuration(for: Date())
    }
    
    private var weekDuration: TimeInterval {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        return tracker.totalDuration(from: startOfWeek, to: endOfWeek)
    }
}

/// Individual stat card
struct StatCard: View {
    let title: String
    let duration: TimeInterval
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(formattedDuration)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
    
    private var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d min", minutes)
        } else {
            return "0 min"
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
}
