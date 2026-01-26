//
//  TimelineStatsView.swift
//  Still Island
//
//  Timeline view showing usage trends with Charts framework.
//

import SwiftUI
import Charts

/// Data point for chart display
struct DailyUsageData: Identifiable {
    let id = UUID()
    let date: Date
    let duration: TimeInterval
    let category: String  // "展示时间" or "离开时间"
    
    var durationMinutes: Double {
        duration / 60.0
    }
}

/// Timeline view with bar chart showing daily usage trends
struct TimelineStatsView: View {
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var timeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "周"
        case month = "月"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Time range picker
            Picker("时间范围", selection: $timeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if chartData.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("暂无数据")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("使用悬浮窗口后会在这里显示统计")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Chart
                Chart(chartData) { data in
                    BarMark(
                        x: .value("日期", data.date, unit: .day),
                        y: .value("时长(分钟)", data.durationMinutes)
                    )
                    .foregroundStyle(by: .value("类型", data.category))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: timeRange == .week ? 1 : 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text("\(Int(minutes))m")
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "展示时间": Color.blue,
                    "离开时间": Color.purple
                ])
                .chartLegend(position: .bottom)
                .frame(height: 250)
                .padding(.horizontal)
                
                // Summary below chart
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            Text("展示时间")
                                .font(.caption)
                        }
                        Text(formatDuration(totalDisplayDuration))
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 8, height: 8)
                            Text("离开时间")
                                .font(.caption)
                        }
                        Text(formatDuration(totalAwayDuration))
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .padding(.top)
    }
    
    // MARK: - Computed Properties
    
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date()).addingTimeInterval(86400) // End of today
        let start = calendar.date(byAdding: .day, value: -timeRange.days + 1, to: calendar.startOfDay(for: Date()))!
        return (start, end)
    }
    
    private var chartData: [DailyUsageData] {
        let (start, end) = dateRange
        let dailyTotals = tracker.dailyTotals(from: start, to: end)
        
        var data: [DailyUsageData] = []
        
        for daily in dailyTotals {
            // Add display duration (total - away = active display time)
            let displayDuration = daily.duration - daily.awayDuration
            if displayDuration > 0 {
                data.append(DailyUsageData(
                    date: daily.date,
                    duration: displayDuration,
                    category: "展示时间"
                ))
            }
            
            // Add away duration
            if daily.awayDuration > 0 {
                data.append(DailyUsageData(
                    date: daily.date,
                    duration: daily.awayDuration,
                    category: "离开时间"
                ))
            }
        }
        
        return data
    }
    
    private var totalDisplayDuration: TimeInterval {
        let (start, end) = dateRange
        let dailyTotals = tracker.dailyTotals(from: start, to: end)
        return dailyTotals.reduce(0) { $0 + $1.duration - $1.awayDuration }
    }
    
    private var totalAwayDuration: TimeInterval {
        let (start, end) = dateRange
        let dailyTotals = tracker.dailyTotals(from: start, to: end)
        return dailyTotals.reduce(0) { $0 + $1.awayDuration }
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}

#Preview {
    TimelineStatsView()
}
