//
//  DayDetailView.swift
//  Still Island
//
//  Detailed view showing all sessions for a specific day.
//

import SwiftUI

/// Detailed view for a single day's usage
struct DayDetailView: View {
    let date: Date
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with date and total
            VStack(spacing: 8) {
                Text(formattedDate)
                    .font(.headline)
                
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(formattedTotalDuration)
                            .font(.title2)
                            .fontWeight(.bold)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.blue)
                        Text("总时长")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if totalAwayDuration > 0 {
                        VStack(spacing: 2) {
                            Text(formattedAwayDuration)
                                .font(.title2)
                                .fontWeight(.bold)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.purple)
                            Text("离开时间")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            
            if sessions.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("当日无使用记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
            } else {
                // Timeline visualization
                ScrollView {
                    VStack(spacing: 0) {
                        // Hour markers and sessions
                        TimelineView(sessions: sessions)
                            .padding()
                        
                        // Legend
                        TimelineLegendView()
                            .padding(.horizontal)
                        
                        Divider()
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        // Session list
                        VStack(alignment: .leading, spacing: 12) {
                            Text("详细记录")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)
                            
                            ForEach(sessions, id: \.id) { session in
                                SessionRowView(session: session)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }
                }
            }
        }
        .navigationTitle("日详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var sessions: [DisplaySession] {
        tracker.sessions(for: date)
    }
    
    private var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }
    
    private var totalAwayDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.totalAwayDuration }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private var formattedTotalDuration: String {
        let totalSeconds = Int(totalDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var formattedAwayDuration: String {
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
}

/// Legend for the timeline view
struct TimelineLegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .blue.opacity(0.7), label: "屏幕亮起")
            LegendItem(color: .purple.opacity(0.6), label: "屏幕熄灭")
        }
        .font(.caption)
    }
}

/// Single legend item
struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

/// Timeline visualization showing sessions on a 24-hour scale
struct TimelineView: View {
    let sessions: [DisplaySession]
    
    private let hourHeight: CGFloat = 30
    private let calendar = Calendar.current
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Hour markers
                ForEach(0..<24, id: \.self) { hour in
                    HStack(spacing: 8) {
                        Text(String(format: "%02d:00", hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                    }
                    .offset(y: CGFloat(hour) * hourHeight)
                }
                
                // Session blocks with away intervals
                ForEach(sessions, id: \.id) { session in
                    sessionBlock(for: session, width: geometry.size.width - 60)
                        .offset(x: 50)
                }
            }
        }
        .frame(height: 24 * hourHeight + 20)
    }
    
    @ViewBuilder
    private func sessionBlock(for session: DisplaySession, width: CGFloat) -> some View {
        let startHour = calendar.component(.hour, from: session.startTime)
        let startMinute = calendar.component(.minute, from: session.startTime)
        let startOffset = CGFloat(startHour) * hourHeight + CGFloat(startMinute) / 60.0 * hourHeight
        
        let durationMinutes = session.duration / 60.0
        let blockHeight = max(CGFloat(durationMinutes) / 60.0 * hourHeight, 4) // Min height of 4
        
        let blockWidth = width * 0.8
        let awayIntervals = session.awayIntervals
        
        ZStack(alignment: .topLeading) {
            // Base block (active time - screen on)
            RoundedRectangle(cornerRadius: 4)
                .fill(providerColor(session.providerType).opacity(0.7))
                .frame(width: blockWidth, height: blockHeight)
            
            // Overlay away intervals (screen off)
            ForEach(awayIntervals) { interval in
                if let intervalOffset = calculateIntervalOffset(session: session, interval: interval),
                   let intervalHeight = calculateIntervalHeight(interval: interval, sessionDuration: session.duration, blockHeight: blockHeight) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: blockWidth, height: intervalHeight)
                        .offset(y: intervalOffset)
                }
            }
        }
        .offset(y: startOffset)
    }
    
    private func calculateIntervalOffset(session: DisplaySession, interval: AwayInterval) -> CGFloat? {
        let sessionDuration = session.duration
        guard sessionDuration > 0 else { return nil }
        
        let intervalStartOffset = interval.startTime.timeIntervalSince(session.startTime)
        let relativeOffset = intervalStartOffset / sessionDuration
        
        let durationMinutes = sessionDuration / 60.0
        let blockHeight = max(CGFloat(durationMinutes) / 60.0 * hourHeight, 4)
        
        return CGFloat(relativeOffset) * blockHeight
    }
    
    private func calculateIntervalHeight(interval: AwayInterval, sessionDuration: TimeInterval, blockHeight: CGFloat) -> CGFloat? {
        guard sessionDuration > 0 else { return nil }
        
        let relativeHeight = interval.duration / sessionDuration
        return max(CGFloat(relativeHeight) * blockHeight, 2) // Min height of 2
    }
    
    private func providerColor(_ type: String) -> Color {
        switch type {
        case "time": return .blue
        case "timer": return .green
        default: return .gray
        }
    }
}

/// Row view for individual session in the list
struct SessionRowView: View {
    let session: DisplaySession
    
    var body: some View {
        HStack(spacing: 12) {
            // Provider icon
            Image(systemName: providerIcon)
                .font(.title3)
                .foregroundStyle(providerColor)
                .frame(width: 40, height: 40)
                .background(providerColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Time info
            VStack(alignment: .leading, spacing: 4) {
                Text(providerName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(formattedStartTime) - \(formattedEndTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Duration info
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.formattedDuration)
                    .font(.callout)
                    .fontWeight(.medium)
                    .fontDesign(.monospaced)
                    .foregroundStyle(providerColor)
                
                if session.totalAwayDuration > 0 {
                    Text("离开 \(session.formattedAwayDuration)")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
    
    private var providerIcon: String {
        switch session.providerType {
        case "time": return "clock.fill"
        case "timer": return "timer"
        default: return "questionmark"
        }
    }
    
    private var providerName: String {
        switch session.providerType {
        case "time": return "时钟"
        case "timer": return "计时器"
        default: return session.providerType
        }
    }
    
    private var providerColor: Color {
        switch session.providerType {
        case "time": return .blue
        case "timer": return .green
        default: return .gray
        }
    }
    
    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.startTime)
    }
    
    private var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.endTime ?? Date())
    }
}

#Preview {
    NavigationStack {
        DayDetailView(date: Date())
    }
}
