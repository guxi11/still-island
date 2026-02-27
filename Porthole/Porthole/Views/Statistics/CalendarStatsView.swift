//
//  CalendarStatsView.swift
//  Porthole
//
//  Calendar view showing daily usage with visual indicators.
//

import SwiftUI

// MARK: - Theme Colors (shared across Statistics views)
extension Color {
    /// 海洋蓝 - 代表专注时的屏幕亮起时间，如同平静的海面
    static let statsOceanBlue = Color(red: 0.20, green: 0.55, blue: 0.82)
    /// 珊瑚橙 - 代表休息时间，如同温暖的晚霞
    static let statsAmberGlow = Color(red: 0.95, green: 0.45, blue: 0.35)
    /// 翡翠绿 - 计时器类型
    static let statsJadeGreen = Color(red: 0.25, green: 0.72, blue: 0.58)
    /// 薰衣草紫 - 实景相机类型
    static let statsLavender = Color(red: 0.58, green: 0.44, blue: 0.86)
    /// 蜜桃粉 - 小猫伴侣类型
    static let statsPeachPink = Color(red: 0.96, green: 0.60, blue: 0.55)
    /// 琥珀金 - 视频类型
    static let statsAmberGold = Color(red: 0.95, green: 0.68, blue: 0.25)
    
    /// 日历主色调 - 翡翠绿
    static let calendarThemeColor = Color.statsJadeGreen
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
            VStack(spacing: 24) {
                // Month navigation
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    Spacer()

                    Text(monthYearString)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Calendar grid
                VStack(spacing: 16) {
                    // Weekday headers
                    HStack(spacing: 0) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(daysInMonth, id: \.self) { date in
                            if let date = date {
                                ModernDayCell(
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
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 16)
            }
        }
        .background(Color(.systemBackground))
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

    // MARK: - Helper Functions

    private func intensityColor(level: Int) -> Color {
        switch level {
        case 0: return Color(.systemFill)
        case 1: return Color.calendarThemeColor.opacity(0.25)
        case 2: return Color.calendarThemeColor.opacity(0.50)
        case 3: return Color.calendarThemeColor.opacity(0.75)
        default: return Color.calendarThemeColor
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
        return dailyTotals.map { $0.duration - $0.awayDuration }.max() ?? 0
    }

    private func displayDuration(for date: Date) -> TimeInterval {
        let total = tracker.totalDuration(for: date)
        let away = tracker.totalAwayDuration(for: date)
        return total - away
    }

    // MARK: - Actions

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(.snappy) {
                currentMonth = newMonth
            }
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(.snappy) {
                currentMonth = newMonth
            }
        }
    }
}

/// Modern day cell with minimalistic design
struct ModernDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let duration: TimeInterval
    let maxDuration: TimeInterval

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            // Background - always show duration color if exists
            if duration > 0 {
                Circle()
                    .fill(fillColor)
            } else {
                Circle()
                    .fill(Color.clear)
            }

            // Selection Indicator (Ring)
            if isSelected {
                Circle()
                    .stroke(Color.calendarThemeColor, lineWidth: 2)
            } else if isToday {
                // Today indicator (lighter ring if not selected)
                Circle()
                    .stroke(Color.calendarThemeColor.opacity(0.5), lineWidth: 1.5)
            }

            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 15, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                .foregroundStyle(textColor)
        }
        .aspectRatio(1, contentMode: .fill)
    }

    private var fillColor: Color {
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        // 使用更柔和的绿色渐变
        return Color.calendarThemeColor.opacity(0.15 + (intensity * 0.6))
    }

    private var textColor: Color {
        // 如果有数据，文字颜色根据背景深浅决定
        if duration > 0 {
            let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
            return intensity > 0.6 ? .white : .primary
        }
        // 无数据时，选中或今日显示主题色
        if isSelected || isToday {
            return Color.calendarThemeColor
        }
        return .primary
    }
}

#Preview {
    NavigationStack {
        CalendarStatsView(selectedDate: .constant(Date()))
    }
}
