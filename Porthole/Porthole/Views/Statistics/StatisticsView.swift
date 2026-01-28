//
//  StatisticsView.swift
//  Porthole
//
//  Main statistics view - iOS Screen Time inspired design.
//

import SwiftUI
import SwiftData
import Charts

// Note: Theme colors (statsOceanBlue, statsAmberGlow, statsJadeGreen) are defined
// in CalendarStatsView.swift as a public Color extension

/// Main statistics view with bar chart header - iOS Screen Time style
struct StatisticsView: View {
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var selectedDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Bar chart card
                chartCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Daily breakdown
                dailyBreakdown
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("使用统计")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Chart Card
    
    private var chartCard: some View {
        VStack(spacing: 16) {
            // Total duration display - show both display and away time
            HStack(alignment: .top, spacing: 24) {
                // Display time (primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedTotalDisplayDuration)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.statsOceanBlue)
                            .frame(width: 10, height: 10)
                        Text("预览生活")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Away time (secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedTotalAwayDuration)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.statsAmberGlow)
                            .frame(width: 10, height: 10)
                        Text("回归生活")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Stacked bar chart - shows both display and away time
            Chart(chartData) { item in
                // Display time (ocean blue - 预览生活)
                BarMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("时长", item.displayMinutes)
                )
                .foregroundStyle(item.isSelected ? Color.statsOceanBlue : Color.statsOceanBlue.opacity(0.45))
                .cornerRadius(4)
                
                // Away time (amber glow - 休息时间) - stacked on top
                BarMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("时长", item.awayMinutes)
                )
                                .foregroundStyle(item.isSelected ? Color.statsAmberGlow : Color.statsAmberGlow.opacity(0.40))
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatDateLabel(date))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(formatAxisLabelChinese(minutes))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let plotFrame = proxy.plotFrame {
                            let plotArea = geometry[plotFrame]
                            let xInPlot = location.x - plotArea.origin.x
                            if let date = proxy.value(atX: xInPlot, as: Date.self) {
                                selectedDate = Calendar.current.startOfDay(for: date)
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if let plotFrame = proxy.plotFrame {
                                    let plotArea = geometry[plotFrame]
                                    let xInPlot = value.location.x - plotArea.origin.x
                                    if let date = proxy.value(atX: xInPlot, as: Date.self) {
                                        selectedDate = Calendar.current.startOfDay(for: date)
                                    }
                                }
                            }
                    )
            }
        }
            .frame(height: 160)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Daily Breakdown
    
    private var dailyBreakdown: some View {
        VStack(spacing: 0) {
            // Selected date header
            HStack {
                Text(formattedSelectedDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            // Stats for selected date
            VStack(spacing: 0) {
                statRow(
                    title: "预览生活",
                    duration: selectedDayDisplayDuration,
                    color: .statsOceanBlue
                )
                
                Divider()
                    .padding(.leading, 20)
                
                statRow(
                    title: "回归生活",
                    duration: selectedDayAwayDuration,
                    color: .statsAmberGlow
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            
            // Calendar link
            NavigationLink {
                CalendarStatsView(selectedDate: $selectedDate)
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.statsOceanBlue)
                    Text("查看日历")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Spacer(minLength: 40)
        }
    }
    
    private func statRow(title: String, duration: TimeInterval, color: Color) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 20)
            
            Text(title)
                .font(.system(size: 15))
            
            Spacer()
            
            Text(formatDuration(duration))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Computed Properties
    
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date()).addingTimeInterval(86400)
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
        return (start, end)
    }
    
    private var chartData: [DailyChartData] {
        let calendar = Calendar.current
        let (start, end) = dateRange
        let dailyTotals = tracker.dailyTotals(from: start, to: end)
        
        // Create dictionaries for quick lookup
        var dataByDate: [Date: (duration: TimeInterval, awayDuration: TimeInterval)] = [:]
        for daily in dailyTotals {
            let dayStart = calendar.startOfDay(for: daily.date)
            dataByDate[dayStart] = (daily.duration, daily.awayDuration)
        }
        
        // Generate all days in range
        var data: [DailyChartData] = []
        var currentDate = start
        while currentDate < end {
            let dayData = dataByDate[currentDate]
            let totalDuration = dayData?.duration ?? 0
            let awayDuration = dayData?.awayDuration ?? 0
            let displayDuration = totalDuration - awayDuration
            let isSelected = calendar.isDate(currentDate, inSameDayAs: selectedDate)
            data.append(DailyChartData(
                date: currentDate,
                displayDuration: displayDuration,
                awayDuration: awayDuration,
                isSelected: isSelected
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return data
    }
    
    private var totalDisplayDuration: TimeInterval {
        let (start, end) = dateRange
        let total = tracker.totalDuration(from: start, to: end)
        let away = tracker.totalAwayDuration(from: start, to: end)
        return total - away
    }
    
    private var totalAwayDuration: TimeInterval {
        let (start, end) = dateRange
        return tracker.totalAwayDuration(from: start, to: end)
    }
    
    private var selectedDayDisplayDuration: TimeInterval {
        let total = tracker.totalDuration(for: selectedDate)
        let away = tracker.totalAwayDuration(for: selectedDate)
        return total - away
    }
    
    private var selectedDayAwayDuration: TimeInterval {
        tracker.totalAwayDuration(for: selectedDate)
    }
    
    private var formattedTotalDisplayDuration: String {
        formatDurationChinese(totalDisplayDuration)
    }
    
    private var formattedTotalAwayDuration: String {
        formatDurationChinese(totalAwayDuration)
    }
    
    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(selectedDate) {
            return "今天"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "昨天"
        } else {
            formatter.dateFormat = "M月d日 EEEE"
            return formatter.string(from: selectedDate)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "0分钟"
        }
    }
    
    private func formatDurationChinese(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)时\(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }
    
    private func formatAxisLabelChinese(_ minutes: Double) -> String {
        if minutes >= 60 {
            return "\(Int(minutes / 60))时"
        } else {
            return "\(Int(minutes))分"
        }
    }
    
    private func formatDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今"
        } else if calendar.isDateInYesterday(date) {
            return "昨"
        } else {
            let day = calendar.component(.day, from: date)
            return "\(day)日"
        }
    }
}

/// Data model for chart - includes both display and away time
struct DailyChartData: Identifiable {
    let id = UUID()
    let date: Date
    let displayDuration: TimeInterval
    let awayDuration: TimeInterval
    let isSelected: Bool
    
    var displayMinutes: Double {
        displayDuration / 60.0
    }
    
    var awayMinutes: Double {
        awayDuration / 60.0
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
}
