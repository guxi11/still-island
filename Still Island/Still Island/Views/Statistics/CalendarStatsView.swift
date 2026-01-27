//
//  CalendarStatsView.swift
//  Still Island
//
//  Calendar view showing daily usage with visual indicators.
//

import SwiftUI

// MARK: - Theme Colors (shared across Statistics views)
extension Color {
    /// 海洋蓝 - 代表专注时的屏幕亮起时间，如同平静的海面
    static let statsOceanBlue = Color(red: 0.20, green: 0.55, blue: 0.82)
    /// 珊瑚橙 - 代表休息时的熄屏时间，如同温暖的晚霞
    static let statsAmberGlow = Color(red: 0.95, green: 0.45, blue: 0.35)
    /// 翡翠绿 - 计时器类型
    static let statsJadeGreen = Color(red: 0.25, green: 0.72, blue: 0.58)
}

/// Calendar view with monthly navigation and usage intensity indication
struct CalendarStatsView: View {
    @Binding var selectedDate: Date
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var currentMonth = Date()
    @State private var showDayDetail = false
    
    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Month navigation
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.statsOceanBlue)
                            .frame(width: 36, height: 36)
                    }
                    
                    Spacer()
                    
                    Text(monthYearString)
                        .font(.system(size: 17, weight: .semibold))
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.statsOceanBlue)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Weekday headers
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                
                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(daysInMonth, id: \.self) { date in
                        if let date = date {
                            DayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                duration: displayDuration(for: date),
                                maxDuration: maxDisplayDurationInMonth
                            )
                            .onTapGesture {
                                selectedDate = date
                                showDayDetail = true
                            }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日历")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDayDetail) {
            NavigationStack {
                DayDetailView(date: selectedDate)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Computed Properties
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }
    
    private var daysInMonth: [Date?] {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private var maxDisplayDurationInMonth: TimeInterval {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        
        let dailyTotals = tracker.dailyTotals(from: startOfMonth, to: endOfMonth)
        // 使用展示时长（总时长 - 熄屏时长）来计算最大值
        return dailyTotals.map { $0.duration - $0.awayDuration }.max() ?? 0
    }
    
    /// 计算指定日期的展示时长（减去熄屏时长）
    private func displayDuration(for date: Date) -> TimeInterval {
        let total = tracker.totalDuration(for: date)
        let away = tracker.totalAwayDuration(for: date)
        return total - away
    }
    
    // MARK: - Actions
    
    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMonth = newMonth
            }
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMonth = newMonth
            }
        }
    }
}

/// Individual day cell in the calendar
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let duration: TimeInterval
    let maxDuration: TimeInterval
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                .foregroundStyle(textColor)
            
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .opacity(duration > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.statsOceanBlue.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isToday ? Color.statsOceanBlue.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
    
    private var dotColor: Color {
        if duration == 0 { return .clear }
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        return Color.statsOceanBlue.opacity(0.4 + (intensity * 0.6))
    }
    
    private var dotSize: CGFloat {
        if duration == 0 { return 0 }
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        return 4 + (CGFloat(intensity) * 4)
    }
    
    private var textColor: Color {
        isToday ? Color.statsOceanBlue : .primary
    }
}

#Preview {
    NavigationStack {
        CalendarStatsView(selectedDate: .constant(Date()))
    }
}
