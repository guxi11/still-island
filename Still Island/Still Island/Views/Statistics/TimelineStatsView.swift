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
    let providerType: String
    
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
                    .foregroundStyle(by: .value("类型", providerDisplayName(data.providerType)))
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
                    "时钟": Color.blue,
                    "计时器": Color.green
                ])
                .chartLegend(position: .bottom)
                .frame(height: 250)
                .padding(.horizontal)
                
                // Summary below chart
                HStack(spacing: 20) {
                    ForEach(providerSummaries, id: \.type) { summary in
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(summary.color)
                                    .frame(width: 8, height: 8)
                                Text(summary.displayName)
                                    .font(.caption)
                            }
                            Text(formatDuration(summary.totalDuration))
                                .font(.callout)
                                .fontWeight(.medium)
                        }
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
            for (providerType, duration) in daily.byProvider {
                if duration > 0 {
                    data.append(DailyUsageData(
                        date: daily.date,
                        duration: duration,
                        providerType: providerType
                    ))
                }
            }
        }
        
        return data
    }
    
    private var providerSummaries: [(type: String, displayName: String, totalDuration: TimeInterval, color: Color)] {
        let (start, end) = dateRange
        let dailyTotals = tracker.dailyTotals(from: start, to: end)
        
        var totals: [String: TimeInterval] = [:]
        for daily in dailyTotals {
            for (providerType, duration) in daily.byProvider {
                totals[providerType, default: 0] += duration
            }
        }
        
        return totals.map { (type, duration) in
            (
                type: type,
                displayName: providerDisplayName(type),
                totalDuration: duration,
                color: providerColor(type)
            )
        }.sorted { $0.totalDuration > $1.totalDuration }
    }
    
    // MARK: - Helper Methods
    
    private func providerDisplayName(_ type: String) -> String {
        switch type {
        case "time": return "时钟"
        case "timer": return "计时器"
        default: return type
        }
    }
    
    private func providerColor(_ type: String) -> Color {
        switch type {
        case "time": return .blue
        case "timer": return .green
        default: return .gray
        }
    }
    
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
