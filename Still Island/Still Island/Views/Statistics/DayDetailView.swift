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
                
                Text(formattedTotalDuration)
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.blue)
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
                        
                        Divider()
                            .padding(.horizontal)
                        
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
                
                // Session blocks
                ForEach(sessions, id: \.id) { session in
                    sessionBlock(for: session, width: geometry.size.width - 60)
                        .offset(x: 50)
                }
            }
        }
        .frame(height: 24 * hourHeight + 20)
    }
    
    private func sessionBlock(for session: DisplaySession, width: CGFloat) -> some View {
        let startHour = calendar.component(.hour, from: session.startTime)
        let startMinute = calendar.component(.minute, from: session.startTime)
        let startOffset = CGFloat(startHour) * hourHeight + CGFloat(startMinute) / 60.0 * hourHeight
        
        let durationMinutes = session.duration / 60.0
        let blockHeight = max(CGFloat(durationMinutes) / 60.0 * hourHeight, 4) // Min height of 4
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(providerColor(session.providerType).opacity(0.7))
            .frame(width: width * 0.8, height: blockHeight)
            .offset(y: startOffset)
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
            
            // Duration
            Text(session.formattedDuration)
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
                .foregroundStyle(providerColor)
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
